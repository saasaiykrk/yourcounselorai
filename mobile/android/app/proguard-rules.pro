# Razorpay Standard Checkout (razorpay_flutter): keep its classes and JavaScript bridge when
# release builds are shrunk. From Razorpay's Android integration guide.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
