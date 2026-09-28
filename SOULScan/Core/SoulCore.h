#ifndef SOUL_CORE_H
#define SOUL_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { float x, y, z; } SoulPoint;
typedef struct { float r[9]; float t[3]; } SoulPose; /* row-major rotation, metres */
typedef struct {
    int32_t status; /* 0 rejected, 1 fused, 2 stationary, 3 point budget reached */
    int32_t point_count, accepted_frames, rejected_frames, view_bins;
    float rms_metres, inlier_ratio;
    SoulPose pose;
} SoulResult;
typedef void *SoulHandle;
SoulHandle soul_create(void);
void soul_destroy(SoulHandle handle);
void soul_reset(SoulHandle handle);
SoulResult soul_add_frame(SoulHandle handle, const SoulPoint *points, int32_t count);
int32_t soul_point_count(SoulHandle handle);
int32_t soul_copy_points(SoulHandle handle, SoulPoint *destination, int32_t capacity);
/* Maps source[i] to target[i]. Returns 0 for invalid or geometrically degenerate input. */
int32_t soul_fit_rigid(const SoulPoint *source, const SoulPoint *target, int32_t count, SoulPose *pose);
#ifdef __cplusplus
}
#endif
#endif
