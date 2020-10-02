// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from libunity.djinni

#pragma once

#include "djinni_support.hpp"
#include "witness_estimate_info_record.hpp"

namespace djinni_generated {

class NativeWitnessEstimateInfoRecord final {
public:
    using CppType = ::WitnessEstimateInfoRecord;
    using JniType = jobject;

    using Boxed = NativeWitnessEstimateInfoRecord;

    ~NativeWitnessEstimateInfoRecord();

    static CppType toCpp(JNIEnv* jniEnv, JniType j);
    static ::djinni::LocalRef<JniType> fromCpp(JNIEnv* jniEnv, const CppType& c);

private:
    NativeWitnessEstimateInfoRecord();
    friend ::djinni::JniClass<NativeWitnessEstimateInfoRecord>;

    const ::djinni::GlobalRef<jclass> clazz { ::djinni::jniFindClass("com/novo/jniunifiedbackend/WitnessEstimateInfoRecord") };
    const jmethodID jconstructor { ::djinni::jniGetMethodID(clazz.get(), "<init>", "(JJJDDJJ)V") };
    const jfieldID field_mNetworkWeight { ::djinni::jniGetFieldID(clazz.get(), "mNetworkWeight", "J") };
    const jfieldID field_mWeight { ::djinni::jniGetFieldID(clazz.get(), "mWeight", "J") };
    const jfieldID field_mParts { ::djinni::jniGetFieldID(clazz.get(), "mParts", "J") };
    const jfieldID field_mEstimatedWitnessProbability { ::djinni::jniGetFieldID(clazz.get(), "mEstimatedWitnessProbability", "D") };
    const jfieldID field_mEstimatedBlocksPerDay { ::djinni::jniGetFieldID(clazz.get(), "mEstimatedBlocksPerDay", "D") };
    const jfieldID field_mEstimatedDailyEarnings { ::djinni::jniGetFieldID(clazz.get(), "mEstimatedDailyEarnings", "J") };
    const jfieldID field_mEstimatedLifetimeEarnings { ::djinni::jniGetFieldID(clazz.get(), "mEstimatedLifetimeEarnings", "J") };
};

}  // namespace djinni_generated