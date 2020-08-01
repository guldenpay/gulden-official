// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from libunity.djinni

#ifndef DJINNI_GENERATED_NJSIWITNESSCONTROLLER_HPP
#define DJINNI_GENERATED_NJSIWITNESSCONTROLLER_HPP


#include "witness_estimate_info_record.hpp"
#include "witness_funding_result_record.hpp"
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>

#include <napi.h>
#include <uv.h>
#include <i_witness_controller.hpp>

using namespace std;

class NJSIWitnessController: public Napi::ObjectWrap<NJSIWitnessController> {
public:

    static Napi::FunctionReference constructor;
    static Napi::Object Init(Napi::Env env, Napi::Object exports);
    NJSIWitnessController(const Napi::CallbackInfo& info) : Napi::ObjectWrap<NJSIWitnessController>(info){};

private:
    /** Get information on min/max witness periods, weights etc. */
    Napi::Value getNetworkLimits(const Napi::CallbackInfo& info);

    /** Get an estimate of weights/parts that a witness account will be funded with */
    Napi::Value getEstimatedWeight(const Napi::CallbackInfo& info);

    /** Fund a witness account */
    Napi::Value fundWitnessAccount(const Napi::CallbackInfo& info);

};
#endif //DJINNI_GENERATED_NJSIWITNESSCONTROLLER_HPP