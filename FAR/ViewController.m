//
//  ViewController.m
//  sample_face_track
//
//  Created by makun on 11/23/14.
//  Copyright (c) 2015 SenseTime.com . All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "CanvasView.h"
#import "time.h"
#import "fartracker.h"

#define __front

typedef struct face_t {
    far_rect_t rect;
    float left_eye_x;
    float left_eye_y;
    float right_eye_x;
    float right_eye_y;
    float mouse_x;
    float mouse_y;
} face_t;

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic , strong) CIContext *context;

@property (nonatomic , strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer ;

@property (nonatomic , strong) CanvasView *viewCanvas ;

@property (nonatomic) far_tracker_t tracker;

@property (nonatomic) face_t start_face;

@property (nonatomic) int drop_count, last_detect, count_detect;

@property (nonatomic) float start_roll;

@end

@implementation ViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor blackColor] ;
    
    self.tracker = NULL;
    self.drop_count = self.last_detect = self.count_detect = 0;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    far_release(self.tracker);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.context = [CIContext contextWithOptions:nil];
    
    far_release(self.tracker);
    self.tracker = NULL;
    
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    
    session.sessionPreset = AVCaptureSessionPreset640x480;
    
    self.captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    self.captureVideoPreviewLayer.frame = CGRectMake( 0, 0, 480, 640 ) ;
    self.captureVideoPreviewLayer.position = self.view.center ;
    [self.captureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [self.view.layer addSublayer:self.captureVideoPreviewLayer];
    
    self.viewCanvas = [[CanvasView alloc] initWithFrame:self.captureVideoPreviewLayer.frame] ;
    [self.view addSubview:self.viewCanvas] ;
    self.viewCanvas.backgroundColor = [UIColor clearColor] ;
    
    AVCaptureDevice *deviceFront ;
    
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if ([device hasMediaType:AVMediaTypeVideo]) {
#ifdef __front
            if ([device position] == AVCaptureDevicePositionFront) {
#else
            if ([device position] == AVCaptureDevicePositionBack) {
#endif
                deviceFront = device;
            }
        }
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:deviceFront error:&error];
    if (!input) {
        // Handle the error appropriately.
        NSLog(@"ERROR: trying to open camera: %@", error);
    }
    AVCaptureVideoDataOutput * dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [dataOutput setMinFrameDuration:CMTimeMake(1, 30)];
    [dataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];

    dispatch_queue_t queue = dispatch_queue_create("bufferQueue", NULL);
    [dataOutput setSampleBufferDelegate:self queue:queue];
    
    [session beginConfiguration];
    if ([session canAddInput:input]) {
        [session addInput:input];
    }
    if ([session canAddOutput:dataOutput]) {
        [session addOutput:dataOutput];
    }
    [session commitConfiguration];
    
    [session startRunning];
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    uint8_t* baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    int iWidth  = (int)CVPixelBufferGetWidth(pixelBuffer);
    int iHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    unsigned char *gray = malloc(iWidth * iHeight);
    for (int i = 0; i < iHeight * iWidth; ++i)
        gray[i] = 0.299f * baseAddress[i * 4 + 2] + 0.587f * baseAddress[i * 4 + 1] + 0.114f * baseAddress[i * 4];
    
    face_t face;
    float l = (iWidth < iHeight ? iWidth : iHeight) * 0.25f;
    face.rect.x = iWidth * 0.5f - l * 0.5f;
    face.rect.y = iHeight * 0.5f - l * 0.5f;
    face.rect.width = face.rect.height = l;
    face.left_eye_x = face.rect.x + face.rect.width * 0.25f;
    face.left_eye_y = face.rect.y + face.rect.height * 0.25f;
    face.right_eye_x = face.rect.x + face.rect.width * 0.75f;
    face.right_eye_y = face.rect.y + face.rect.height * 0.25f;
    face.mouse_x = face.rect.x + face.rect.width * 0.5f;
    face.mouse_y = face.rect.y + face.rect.height * 0.75f;
    if (self.tracker != NULL)
        face = self.start_face;
    
    NSLog(@"new frame %dx%d", iWidth, iHeight);
    if ((self.tracker == NULL || !far_check(self.tracker)) && self.last_detect <= 0) {
        UIDeviceOrientation ori = [[UIDevice currentDevice] orientation];
        int exifOrientation = 6;
        float deviceroll = 0.0f;
#ifdef __front
        switch (ori) {
            case UIDeviceOrientationPortrait:
                exifOrientation = 6;
                deviceroll = 0.0f;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                exifOrientation = 8;
                deviceroll = M_PI;
                break;
            case UIDeviceOrientationLandscapeLeft:
                exifOrientation = 3;
                deviceroll = -M_PI_2;
                break;
            case UIDeviceOrientationLandscapeRight:
                exifOrientation = 1;
                deviceroll = M_PI_2;
                break;
            default:
                break;
        }
#else
        switch (ori) {
            case UIDeviceOrientationPortrait:
                exifOrientation = 5;
                deviceroll = 0.0f;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                exifOrientation = 7;
                deviceroll = M_PI;
                break;
            case UIDeviceOrientationLandscapeLeft:
                exifOrientation = 2;
                deviceroll = M_PI_2;
                break;
            case UIDeviceOrientationLandscapeRight:
                exifOrientation = 4;
                deviceroll = -M_PI_2;
                break;
            default:
                break;
        }
#endif
        NSLog(@"detection orientation = %d", exifOrientation);
        NSDictionary *opts = @{ CIDetectorAccuracy : CIDetectorAccuracyHigh };
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeFace context:self.context options:opts];
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        opts = @{ CIDetectorImageOrientation : [NSNumber numberWithInt:exifOrientation]};
        NSArray *features = [detector featuresInImage:ciImage options:opts];
        self.last_detect = 5;
        ++self.count_detect;
        far_rect_t *far_rects = malloc([features count] * sizeof(far_rect_t));
        face_t *faces = malloc([features count] * sizeof(face_t));
        int n = 0;
        for (CIFaceFeature *f in features) {
            if (!f.hasLeftEyePosition || !f.hasRightEyePosition || !f.hasMouthPosition)
                continue;
            float left_eye_x = f.leftEyePosition.x;
            float left_eye_y = iHeight - f.leftEyePosition.y - 1;
            float right_eye_x = f.rightEyePosition.x;
            float right_eye_y = iHeight - f.rightEyePosition.y - 1;
            float mouse_x = f.mouthPosition.x;
            float mouse_y = iHeight - f.mouthPosition.y - 1;
            if (self.tracker == NULL && fabs(left_eye_x - right_eye_x) > 10 && fabs(left_eye_y - right_eye_y) > 10)
                continue;
            far_rects[n].x = f.bounds.origin.x;
            far_rects[n].y = iHeight - f.bounds.origin.y - f.bounds.size.height;
            far_rects[n].width = f.bounds.size.width;
            far_rects[n].height = f.bounds.size.height;
            faces[n].rect = far_rects[n];
            faces[n].left_eye_x = left_eye_x;
            faces[n].left_eye_y = left_eye_y;
            faces[n].right_eye_x = right_eye_x;
            faces[n].right_eye_y = right_eye_y;
            faces[n].mouse_x = mouse_x;
            faces[n].mouse_y = mouse_y;
            ++n;
        }
        if (n > 0) {
            if (self.tracker != NULL) {
                face.rect = far_retrack(self.tracker, gray, far_rects, n, deviceroll - self.start_roll);
                NSLog(@"re track at (%.0f)", (deviceroll - self.start_roll) / M_PI * 180);
                for (int i = 0; i < n; ++i)
                    NSLog(@"\t[(%.0f,%.0f) %.0fx%.0f]", far_rects[i].x, far_rects[i].y, far_rects[i].width, far_rects[i].height);
            }else {
                face = faces[0];
                self.tracker = far_init(gray, iWidth, iHeight, face.rect);
                self.start_face = face;
                NSLog(@"start track at [(%.0f,%.0f) %.0fx%.0f]", face.rect.x, face.rect.y, face.rect.width, face.rect.height);
                self.start_roll = deviceroll;
            }
        }else {
            if (self.tracker != NULL) {
                face.rect = far_track(self.tracker, gray);
                NSLog(@"track at [(%.0f,%.0f) %.0fx%.0f]", face.rect.x, face.rect.y, face.rect.width, face.rect.height);
            }else
                NSLog(@"detect nothing");
        }
        free(far_rects);
        free(faces);
    }else {
        if (self.tracker != NULL) {
            face.rect = far_track(self.tracker, gray);
            NSLog(@"track at [(%.0f,%.0f) %.0fx%.0f]", face.rect.x, face.rect.y, face.rect.width, face.rect.height);
        }else
            NSLog(@"track nothing");
        --self.last_detect;
    }
    float error = 0.0f, roll = 0.0f, yaw = 0.0f, pitch = 0.0f;
    if (self.tracker != NULL) {
        far_transform(self.tracker, self.start_face.rect, &face.left_eye_x, &face.left_eye_y);
        far_transform(self.tracker, self.start_face.rect, &face.right_eye_x, &face.right_eye_y);
        far_transform(self.tracker, self.start_face.rect, &face.mouse_x, &face.mouse_y);
        far_info(self.tracker, &error, &roll, &yaw, &pitch);
    }
#ifndef __front
    face.rect.y = iHeight - face.rect.width - face.rect.y;
    face.left_eye_y = iHeight - face.left_eye_y;
    face.right_eye_y = iHeight - face.right_eye_y;
    face.mouse_y = iHeight - face.mouse_y;
#endif
    CGRect rectFace = CGRectMake(face.rect.y, face.rect.x, face.rect.height, face.rect.width);
    float angleRotation = roll;
    CGPoint pointLeftEye = CGPointMake(face.left_eye_y, face.left_eye_x);
    CGPoint pointRightEye = CGPointMake(face.right_eye_y, face.right_eye_x);
    CGPoint pointMouse = CGPointMake(face.mouse_y, face.mouse_x);
    NSString* info = [NSString stringWithFormat:@"detection: %d\nerror: %.2f\nroll: %.0f\nyaw: %.0f\npitch: %.0f\n", self.count_detect, error, roll, yaw, pitch];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showFace:rectFace rotation:angleRotation leftEye:pointLeftEye rightEye:pointRightEye mouse:pointMouse info:info];
    } ) ;
    
    free(gray);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void) showFace:(CGRect)face rotation:(float)rotation leftEye:(CGPoint)leftEye rightEye:(CGPoint)rightEye mouse:(CGPoint)mouse info:(NSString*)info
{
    self.viewCanvas.strFace = NSStringFromCGRect(face);
    self.viewCanvas.strRotation = [NSString stringWithFormat:@"%.7f", rotation];
    self.viewCanvas.strLeftEye = NSStringFromCGPoint(leftEye);
    self.viewCanvas.strRightEye = NSStringFromCGPoint(rightEye);
    self.viewCanvas.strMouse = NSStringFromCGPoint(mouse);
    self.viewCanvas.strInfo = info;
    [self.viewCanvas setNeedsDisplay] ;
}

@end
