#ifndef fartracker_h
#define fartracker_h

// C interface

typedef struct far_rect_t {
    float x;
    float y;
    float width;
    float height;
} far_rect_t;

typedef void* far_tracker_t;

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */
    
    far_tracker_t far_init(const unsigned char *gray, int width, int height, far_rect_t rect);
    far_rect_t far_track(far_tracker_t tracker, const unsigned char *gray);
    far_rect_t far_retrack(far_tracker_t tracker, const unsigned char *gray, const far_rect_t rects[], int n_rects, float roll);
    void far_transform(far_tracker_t tracker, far_rect_t start_rect, float *x, float *y);
    void far_info(far_tracker_t tracker, float *error, float *roll, float *yaw, float *pitch);
    bool far_check(far_tracker_t tracker);
    void far_release(far_tracker_t tracker);
    
#ifdef __cplusplus
}
#endif /* __cplusplus */

// C++ implementation

#ifdef __cplusplus

#include <iostream>
#include <vector>
#include <queue>
#include <cmath>
#include <cstring>
#include <cfloat>
using namespace std;

#include "Eigen/Dense"
using namespace Eigen;

const float PI_2 = acos(-1.0f) * 0.5f;

//#define __front

/*
#ifdef __front
//prefer 320x180 30fps
const int cell_min = 1;
const int fast_n = 16;
const int fast_step = 4;
const int fine_n = 81;
const int cell_n = 81;
const int fine_steps[] = { 60, 20, 5, 1 };
const int detect_interval = 20;
const int max_iteration = 4;
const float padding = 1.6f;
const float sigmoid_factor = 7.141f;
const float sigmoid_bias = 0.482f;
const float translate_eps = 1.0f;
const float error_eps = 0.01f;
const float fine_threshold = 0.4f;
const float fast_threshold = 0.6f;
const float detect_threshold = 0.6f;
#else
//prefer 640x360 15fps
*/
const int cell_min = 1;
const int fast_n = 25;
const int fast_step = 2;
const int fine_n = 361;
const int cell_n = 180;
const int fine_steps[] = { 27, 9, 3, 1 };
const int detect_interval = 10;
const int max_iteration = 9;
const float padding = 1.6f;
const float sigmoid_factor = 7.141f;
const float sigmoid_bias = 0.482f;
const float translate_eps = 0.005f;
const float error_eps = 0.001f;
const float fine_threshold = 0.4f;
const float fast_threshold = 0.4f;
const float detect_threshold = 0.4f;
//#endif /* __front */

typedef Matrix<float, 8, 1> Vector8f;
typedef Matrix<float, 32, 1> Vector32f;

float rectArea(far_rect_t rect);
float rectOverlap(far_rect_t a, far_rect_t b);
ostream& operator<<(ostream& cout, const far_rect_t &rect);

template<typename T, int channels>
class Data
{
public:
    Data(int rows, int cols)
    {
        this->rows = rows;
        this->cols = cols;
        step0 = channels;
        step1 = cols * step0;
        step2 = rows * step1;
        _data = new T[rows * cols * channels];
    }
    
    ~Data()
    {
        delete _data;
    }
    
    void set(T val)
    {
        for (int i = 0; i < step2; ++i)
            _data[i] = val;
    }
    
    T* data()
    {
        return _data;
    }
    
    T* ptr(int row)
    {
        return _data + row * step1;
    }
    
    T* ptr(int row, int col)
    {
        return _data + row * step1 + col * step0;
    }
    
    T& operator()(int index)
    {
        return _data[index];
    }
    
    T& operator()(int row, int col)
    {
        return _data[row * step1 + col];
    }
    
    T& operator()(int row, int col, int channel)
    {
        return _data[row * step1 + col * step0 + channel];
    }
    
public:
    int rows, cols;
    int step0, step1, step2;
    
private:
    T* _data;
};

class Surf
{
public:
    Surf(int width, int height);
    
    void rotate(float angle, float kernel[]);
    void process(const unsigned char *gray, float angle);
    void set_cell(float cell);
    void set_step(int step);
    
    inline float* cell_hist(int x, int y);
    inline void descriptor(float x, float y, float *f);
    inline void gradient(float x, float y, float *f, float *dx, float *dy);
    void descriptor4(float x, float y, float *f);
    void gradient4(float x, float y, float *f, float *dx, float *dy);
    
public:
    float A, X[4], Y[4];
    int W, H, C, step;
    
private:
    Data<float, 1> img;
    Data<int, 1> flag;
    Data<float, 8> sum, hist, zero;
};

class Warp
{
public:
    Warp(int width, int height);
    
    void setr(Vector3f rotate);
    void sett(Vector3f translate);
    
    Vector2f project(Vector3f p);
    Vector3f transform(Vector3f p);
    Vector2f transform2(Vector3f p);
    
    inline Vector2f gradient(Vector3f p, Matrix<float, 2, 6> &dW);
    void steepest(Matrix<float, 6, 1> parameters);
    void euler(float &roll, float &yaw, float &pitch);
    
public:
    Vector2f c;
    float f;
    Vector3f r;
    Vector3f t;
    
private:
    Matrix3f R, Dx, Dy, Dz;
};

class FARTracker
{
public:
    FARTracker(const unsigned char *gray, int width, int height, far_rect_t rect, ostream *os = NULL);
    far_rect_t track(const unsigned char *gray);
    far_rect_t retrack(const unsigned char *gray, const vector<far_rect_t> &detections, float roll);
    bool check();
    
private:
    Vector3f locate(far_rect_t rect);
    far_rect_t window(Vector3f translate);
    
    void update(Warp w, float e);
    void fast_train(Warp w);
    void fine_train(Warp w);
    Vector3f fast_test(Warp w);
    Warp fine_test(Warp w);
    
    inline float sigmoid(float x);
    inline void hessian(Matrix<float, 6, 6> &H, float w, const Matrix<float, 2, 6> &dW, const Matrix<float, 32, 2> &dF);
    
    Warp Lucas_Kanade(Warp w);
    float evaluate(Warp w);
    
public:
    int image_width, image_height;
    float window_width, window_height;
    Warp warp;
    float error, roll, yaw, pitch;
    
private:
    Surf feature;
    vector<Vector2i> fast_samples;
    vector<Vector3f> fine_samples;
    MatrixXf fast_model, fine_model;
    deque<float> fine_errors;
    ostream *log;
    int N;
};

#endif /* __cplusplus */

#endif /* fartracker_h */
