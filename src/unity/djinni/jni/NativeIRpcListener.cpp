// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from libunity.djinni

#include "NativeIRpcListener.hpp"  // my header
#include "Marshal.hpp"

namespace djinni_generated {

NativeIRpcListener::NativeIRpcListener() : ::djinni::JniInterface<::IRpcListener, NativeIRpcListener>() {}

NativeIRpcListener::~NativeIRpcListener() = default;

NativeIRpcListener::JavaProxy::JavaProxy(JniType j) : Handle(::djinni::jniGetThreadEnv(), j) { }

NativeIRpcListener::JavaProxy::~JavaProxy() = default;

void NativeIRpcListener::JavaProxy::onFilteredCommand(const std::string & c_filteredCommand) {
    auto jniEnv = ::djinni::jniGetThreadEnv();
    ::djinni::JniLocalScope jscope(jniEnv, 10);
    const auto& data = ::djinni::JniClass<::djinni_generated::NativeIRpcListener>::get();
    jniEnv->CallVoidMethod(Handle::get().get(), data.method_onFilteredCommand,
                           ::djinni::get(::djinni::String::fromCpp(jniEnv, c_filteredCommand)));
    ::djinni::jniExceptionCheck(jniEnv);
}
void NativeIRpcListener::JavaProxy::onSuccess(const std::string & c_filteredCommand, const std::string & c_result) {
    auto jniEnv = ::djinni::jniGetThreadEnv();
    ::djinni::JniLocalScope jscope(jniEnv, 10);
    const auto& data = ::djinni::JniClass<::djinni_generated::NativeIRpcListener>::get();
    jniEnv->CallVoidMethod(Handle::get().get(), data.method_onSuccess,
                           ::djinni::get(::djinni::String::fromCpp(jniEnv, c_filteredCommand)),
                           ::djinni::get(::djinni::String::fromCpp(jniEnv, c_result)));
    ::djinni::jniExceptionCheck(jniEnv);
}
void NativeIRpcListener::JavaProxy::onError(const std::string & c_errorMessage) {
    auto jniEnv = ::djinni::jniGetThreadEnv();
    ::djinni::JniLocalScope jscope(jniEnv, 10);
    const auto& data = ::djinni::JniClass<::djinni_generated::NativeIRpcListener>::get();
    jniEnv->CallVoidMethod(Handle::get().get(), data.method_onError,
                           ::djinni::get(::djinni::String::fromCpp(jniEnv, c_errorMessage)));
    ::djinni::jniExceptionCheck(jniEnv);
}

}  // namespace djinni_generated