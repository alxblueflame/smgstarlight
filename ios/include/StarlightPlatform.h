#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct StarlightInputState
{
  float move_x;
  float move_y;
  float pointer_x;
  float pointer_y;
  float gyro_x;
  float gyro_y;
  float gyro_z;
  uint32_t buttons;
} StarlightInputState;

enum
{
  STARLIGHT_BUTTON_A = 1u << 0,
  STARLIGHT_BUTTON_B = 1u << 1,
  STARLIGHT_BUTTON_Z = 1u << 2,
  STARLIGHT_BUTTON_C = 1u << 3,
  STARLIGHT_BUTTON_SPIN = 1u << 4,
  STARLIGHT_BUTTON_PLUS = 1u << 5,
  STARLIGHT_BUTTON_MINUS = 1u << 6,
  STARLIGHT_BUTTON_HOME = 1u << 7,
  STARLIGHT_BUTTON_DPAD_UP = 1u << 8,
  STARLIGHT_BUTTON_DPAD_DOWN = 1u << 9,
  STARLIGHT_BUTTON_DPAD_LEFT = 1u << 10,
  STARLIGHT_BUTTON_DPAD_RIGHT = 1u << 11,
};

typedef struct StarlightRuntimeHost
{
  const char* game_path;
  const char* user_path;
  const char* texture_path;
  void* metal_layer;
  StarlightInputState (*read_input)(void);
  uint32_t (*write_audio)(const float* interleaved_stereo, uint32_t frames);
  void (*play_haptic)(float intensity, float duration_seconds);
} StarlightRuntimeHost;

bool starlight_runtime_start(const StarlightRuntimeHost* host);
void starlight_runtime_stop(void);
void starlight_runtime_pause(bool paused);
void starlight_runtime_resize(uint32_t output_width, uint32_t output_height,
                              uint32_t render_width, uint32_t render_height);

StarlightInputState starlight_platform_read_input(void);
uint32_t starlight_platform_write_audio(const float* samples, uint32_t frames);
void starlight_platform_play_haptic(float intensity, float duration_seconds);

#ifdef __cplusplus
}
#endif
