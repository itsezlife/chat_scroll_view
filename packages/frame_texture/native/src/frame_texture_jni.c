/*
 * The JNI side of the table: dev.chatscrollview.frame_texture.FrameTextureNative.
 * Android only; the plugin's Kotlin calls these on the platform thread.
 */
#include <android/native_window_jni.h>
#include <jni.h>

#include "frame_texture.h"

JNIEXPORT jint JNICALL
Java_dev_chatscrollview_frame_1texture_FrameTextureNative_attach(
    JNIEnv* env, jclass clazz, jlong id, jobject surface, jint width,
    jint height) {
  (void)clazz;
  if (surface == NULL) return FRAME_TEXTURE_INVALID;
  /* A reference of our own, which attach takes over. */
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == NULL) return FRAME_TEXTURE_INVALID;
  return frame_texture_attach((int64_t)id, window, width, height);
}

JNIEXPORT void JNICALL
Java_dev_chatscrollview_frame_1texture_FrameTextureNative_detach(
    JNIEnv* env, jclass clazz, jlong id) {
  (void)env;
  (void)clazz;
  frame_texture_detach((int64_t)id);
}

JNIEXPORT void JNICALL
Java_dev_chatscrollview_frame_1texture_FrameTextureNative_forget(
    JNIEnv* env, jclass clazz, jlong id) {
  (void)env;
  (void)clazz;
  frame_texture_forget((int64_t)id);
}

JNIEXPORT jint JNICALL
Java_dev_chatscrollview_frame_1texture_FrameTextureNative_count(JNIEnv* env,
                                                                jclass clazz) {
  (void)env;
  (void)clazz;
  return frame_texture_count();
}
