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
#import "fartracker.h"

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

@property (nonatomic) int last_detect;

@end

@implementation ViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor blackColor] ;
    
    self.tracker = NULL;
    self.last_detect = 0;
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
            
            if ([device position] == AVCaptureDevicePositionFront) {
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
    
    /*
    NSData *data = [NSData dataWithBytes:gray length:iWidth * iHeight];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGImageRef imageRef = CGImageCreate(iWidth,                                 //width
                                        iHeight,                                 //height
                                        8,                                          //bits per component
                                        8,                       //bits per pixel
                                        iWidth,                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
     */
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
        NSDictionary *opts = @{ CIDetectorAccuracy : CIDetectorAccuracyHigh };
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeFace context:self.context options:opts];
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        opts = @{ CIDetectorImageOrientation : [NSNumber numberWithInt:1]};
        NSArray *features = [detector featuresInImage:ciImage options:opts];
        self.last_detect = 30;
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
            float dx = 2 * mouse_x - left_eye_x - right_eye_x;
            float dy = left_eye_y - right_eye_y;
            if (dx * dx + dy * dy > (f.bounds.size.height * f.bounds.size.width) / 10)
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
            if (self.tracker == NULL) {
                face = faces[0];
                self.tracker = far_init(gray, iWidth, iHeight, face.rect);
                self.start_face = face;
                NSLog(@"start track at [(%.0f,%.0f) %.0fx%.0f]", face.rect.x, face.rect.y, face.rect.width, face.rect.height);
            }else {
                NSLog(@"re track at");
                for (int i = 0; i < n; ++i)
                    NSLog(@"\t[(%.0f,%.0f) %.0fx%.0f]", far_rects[i].x, far_rects[i].y, far_rects[i].width, far_rects[i].height);
                face.rect = far_retrack(self.tracker, gray, far_rects, n);
            }
        }else
            NSLog(@"detect nothing");
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
    if (self.tracker != NULL) {
        far_transform(self.tracker, self.start_face.rect, &face.left_eye_x, &face.left_eye_y);
        far_transform(self.tracker, self.start_face.rect, &face.right_eye_x, &face.right_eye_y);
        far_transform(self.tracker, self.start_face.rect, &face.mouse_x, &face.mouse_y);
    }

    CGRect rectFace = CGRectMake(face.rect.y, face.rect.x, face.rect.height, face.rect.width);
    CGPoint pointLeftEye = CGPointMake(face.left_eye_y, face.left_eye_x);
    CGPoint pointRightEye = CGPointMake(face.right_eye_y, face.right_eye_x);
    CGPoint pointMouse = CGPointMake(face.mouse_y, face.mouse_x);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showFace:rectFace leftEye:pointLeftEye rightEye:pointRightEye mouse:pointMouse];
    } ) ;
    
    free(gray);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void) showFace:(CGRect)face leftEye:(CGPoint)leftEye rightEye:(CGPoint)rightEye mouse:(CGPoint)mouse
{
    self.viewCanvas.strFace = NSStringFromCGRect(face);
    self.viewCanvas.strLeftEye = NSStringFromCGPoint(leftEye);
    self.viewCanvas.strRightEye = NSStringFromCGPoint(rightEye);
    self.viewCanvas.strMouse = NSStringFromCGPoint(mouse);
    [self.viewCanvas setNeedsDisplay] ;
}

@end
