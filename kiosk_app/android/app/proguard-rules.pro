# TensorFlow Lite GPU delegate is an optional dependency pulled in by
# tflite_flutter / google_mlkit; the GPU artifact isn't bundled, so R8
# can't resolve these classes. They're only referenced from a fallback
# code path that's never hit without the GPU delegate on the classpath.
-dontwarn org.tensorflow.lite.gpu.**
