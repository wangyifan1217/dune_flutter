-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep class com.tencent.android.tpush.** { *; }
-keep class com.tencent.tpns.baseapi.** { *; }
-keep class com.tencent.tpns.mqttchannel.** { *; }
-keep class com.tencent.tpns.dataacquisition.** { *; }
# TPNS 防混淆辅助类（部分机型不存在，R8 缺类时忽略告警）
-keep class com.jg.** { *; }
-dontwarn com.jg.**

# mobile_scanner / CameraX / ML Kit barcode scanner release 保留规则。
# 部分机型在 release 构建下内部扫码类被优化后会抛出空引用（如 v7.*）。
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class androidx.camera.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**
-dontwarn androidx.camera.**
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.vision.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode_bundled.**
