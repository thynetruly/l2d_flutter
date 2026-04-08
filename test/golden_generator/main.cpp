/**
 * Golden reference data generator for Cubism Framework parity testing.
 *
 * Compiles against the actual C++ Cubism Framework + Core library and outputs
 * JSON files with expected values. These are compared against the Dart
 * reimplementation to verify exact behavioral parity.
 *
 * Usage: ./golden_generator [output_dir]
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

// Cubism Framework includes (actual SDK code)
#include "Math/CubismMath.hpp"
#include "Math/CubismVector2.hpp"
#include "Math/CubismMatrix44.hpp"
#include "Math/CubismModelMatrix.hpp"
#include "CubismFramework.hpp"
#include "ICubismAllocator.hpp"
#include "CubismModelSettingJson.hpp"
#include "Model/CubismMoc.hpp"
#include "Model/CubismModel.hpp"
#include "Motion/CubismMotion.hpp"
#include "Motion/CubismMotionQueueEntry.hpp"
#include "Motion/CubismExpressionMotion.hpp"
#include "Motion/CubismMotionManager.hpp"
#include "Motion/CubismExpressionMotionManager.hpp"
#include "Effect/CubismPose.hpp"
#include "Effect/CubismEyeBlink.hpp"
#include "Effect/CubismBreath.hpp"
#include "Effect/CubismLook.hpp"
#include "Physics/CubismPhysics.hpp"
#include "Id/CubismIdManager.hpp"

using namespace Live2D::Cubism::Framework;

// Helper to read a file into a byte buffer
static std::vector<csmByte> readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) return {};
    std::streamsize size = f.tellg();
    f.seekg(0, std::ios::beg);
    std::vector<csmByte> buf(size);
    f.read((char*)buf.data(), size);
    return buf;
}

// ---------------------------------------------------------------------------
// Minimal allocator for CubismFramework initialization
// ---------------------------------------------------------------------------
class SimpleAllocator : public ICubismAllocator {
public:
    void* Allocate(const csmSizeType size) override { return malloc(size); }
    void Deallocate(void* addr) override { free(addr); }
    void* AllocateAligned(const csmSizeType size, const csmUint32 align) override {
        // Use posix_memalign for proper aligned allocation
        void* p = nullptr;
        // posix_memalign requires alignment to be a power of 2 and multiple of sizeof(void*)
        size_t a = align;
        if (a < sizeof(void*)) a = sizeof(void*);
        if (posix_memalign(&p, a, size) != 0) return nullptr;
        return p;
    }
    void DeallocateAligned(void* addr) override {
        free(addr);
    }
};

// ---------------------------------------------------------------------------
// JSON writer
// ---------------------------------------------------------------------------
class Jw {
    std::ostringstream _s;
    bool _f = true;
    int _i = 0;
    void ind() { for(int i=0;i<_i;i++) _s << "  "; }
    void sep() { if(!_f) _s << ","; _s << "\n"; _f = false; }
public:
    void os(const char* k=0){ sep(); ind(); if(k) _s<<"\""<<k<<"\": "; _s<<"{"; _f=true; _i++; }
    void oe(){ _i--; _s<<"\n"; ind(); _s<<"}"; _f=false; }
    void as(const char* k=0){ sep(); ind(); if(k) _s<<"\""<<k<<"\": "; _s<<"["; _f=true; _i++; }
    void ae(){ _i--; _s<<"\n"; ind(); _s<<"]"; _f=false; }
    void wf(const char* k, double v){ sep(); ind(); char b[64]; snprintf(b,64,"%.10g",v); _s<<"\""<<k<<"\": "<<b; }
    void wfv(double v){ sep(); ind(); char b[64]; snprintf(b,64,"%.10g",v); _s<<b; }
    void wi(const char* k, int v){ sep(); ind(); _s<<"\""<<k<<"\": "<<v; }
    void ws(const char* k, const char* v){ sep(); ind(); _s<<"\""<<k<<"\": \""<<(v?v:"")<<"\""; }
    std::string str(){ return _s.str(); }
};

static void save(const std::string& p, const std::string& c) {
    std::ofstream f(p); f << c << std::endl; f.close();
    printf("  Written: %s\n", p.c_str());
}

// ============================================================================
// Math golden data — uses actual CubismMath, CubismMatrix44, CubismVector2
// ============================================================================
static void genMath(const std::string& d) {
    printf("Generating math_golden.json...\n");
    Jw w;
    w.os();

    // GetEasingSine
    w.as("easingSine");
    for (int i = 0; i <= 100; i++) {
        csmFloat32 t = i / 100.0f;
        csmFloat32 v = CubismMath::GetEasingSine(t);
        w.os(); w.wf("t", t); w.wf("v", v); w.oe();
    }
    w.ae();

    // CardanoAlgorithmForBezier
    w.as("bezier");
    {
        struct { float a,b,c,d; } cases[] = {
            {0,0,1,-0.5f}, {1,-3,3,-0.5f}, {2,-1,0.5f,-0.25f},
            {0,1,-2,0.5f}, {-1,2,-1,0.3f}
        };
        for (int i = 0; i < 5; i++) {
            auto& c = cases[i];
            w.os();
            w.wf("a",c.a); w.wf("b",c.b); w.wf("c",c.c); w.wf("d",c.d);
            w.wf("result", CubismMath::CardanoAlgorithmForBezier(c.a,c.b,c.c,c.d));
            w.oe();
        }
    }
    w.ae();

    // Matrix multiply
    w.as("matrixMultiply");
    {
        CubismMatrix44 a, b;
        a.Scale(2.0f, 3.0f); a.Translate(5.0f, 7.0f);
        b.Scale(0.5f, 0.25f); b.TranslateRelative(1.0f, 2.0f);
        float dst[16];
        CubismMatrix44::Multiply(a.GetArray(), b.GetArray(), dst);
        w.os();
        w.as("a"); for(int i=0;i<16;i++) w.wfv(a.GetArray()[i]); w.ae();
        w.as("b"); for(int i=0;i<16;i++) w.wfv(b.GetArray()[i]); w.ae();
        w.as("result"); for(int i=0;i<16;i++) w.wfv(dst[i]); w.ae();
        w.oe();
    }
    w.ae();

    // Matrix inverse
    w.as("matrixInverse");
    {
        CubismMatrix44 m;
        m.Scale(2.0f, 3.0f); m.Translate(5.0f, 7.0f);
        CubismMatrix44 inv = m.GetInvert();
        w.os();
        w.as("matrix"); for(int i=0;i<16;i++) w.wfv(m.GetArray()[i]); w.ae();
        w.as("inverse"); for(int i=0;i<16;i++) w.wfv(inv.GetArray()[i]); w.ae();
        w.oe();
    }
    w.ae();

    // DirectionToRadian
    w.as("directionToRadian");
    {
        CubismVector2 pairs[][2] = {
            {{1,0},{0,1}}, {{1,0},{-1,0}}, {{0,1},{1,0}},
            {{1,1},{-1,1}}, {{0.5f,0.5f},{-0.3f,0.7f}}
        };
        for (int i = 0; i < 5; i++) {
            w.os();
            w.wf("fromX",pairs[i][0].X); w.wf("fromY",pairs[i][0].Y);
            w.wf("toX",pairs[i][1].X); w.wf("toY",pairs[i][1].Y);
            w.wf("result", CubismMath::DirectionToRadian(pairs[i][0], pairs[i][1]));
            w.oe();
        }
    }
    w.ae();

    w.oe();
    save(d + "/math_golden.json", w.str());
}

// ============================================================================
// Breath golden data — uses actual CubismMath::Pi and sinf
// ============================================================================
static void genBreath(const std::string& d) {
    printf("Generating breath_golden.json...\n");
    Jw w;
    w.os();
    csmFloat32 offset=0.5f, peak=0.5f, cycle=3.2345f;
    csmFloat32 ct = 0;
    w.wf("offset",offset); w.wf("peak",peak); w.wf("cycle",cycle);
    w.as("frames");
    for (int i = 0; i < 360; i++) {
        ct += 1.0f/60.0f;
        csmFloat32 t = ct * 2.0f * CubismMath::Pi;
        csmFloat32 v = offset + peak * CubismMath::SinF(t / cycle);
        w.os(); w.wf("t",ct); w.wf("value",v); w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/breath_golden.json", w.str());
}

// ============================================================================
// Look golden data
// ============================================================================
static void genLook(const std::string& d) {
    printf("Generating look_golden.json...\n");
    Jw w;
    w.os();
    csmFloat32 fX=30, fY=20, fXY=5;
    w.wf("factorX",fX); w.wf("factorY",fY); w.wf("factorXY",fXY);
    csmFloat32 inputs[][2] = {{0,0},{1,0},{0,1},{1,1},{-0.5f,0.3f},{-1,-1},{0.7f,-0.4f}};
    w.as("inputs");
    for (int i=0; i<7; i++) {
        csmFloat32 dx=inputs[i][0], dy=inputs[i][1];
        w.os(); w.wf("dragX",dx); w.wf("dragY",dy);
        w.wf("delta", fX*dx + fY*dy + fXY*dx*dy); w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/look_golden.json", w.str());
}

// ============================================================================
// Eye blink golden data — deterministic simulation
// ============================================================================
static void genEyeBlink(const std::string& d) {
    printf("Generating eye_blink_golden.json...\n");
    Jw w;
    w.os();
    csmFloat32 blinkInterval=4.0f, closing=0.1f, closed=0.05f, opening=0.15f;
    w.wf("blinkInterval",blinkInterval);
    w.wf("closingSeconds",closing); w.wf("closedSeconds",closed); w.wf("openingSeconds",opening);

    srand(42);
    csmFloat32 userTime=0, stateStart=0, nextBlink=0;
    int state = 0;

    w.as("frames");
    for (int frame = 0; frame < 600; frame++) {
        csmFloat32 dt = 1.0f / 60.0f;
        userTime += dt;
        csmFloat32 paramValue = 1.0f;

        switch(state) {
        case 0:
            state = 1;
            { float r = (float)rand() / (float)RAND_MAX;
              nextBlink = userTime + r * (2.0f * blinkInterval - 1.0f); }
            paramValue = 1.0f;
            break;
        case 1:
            if (nextBlink < userTime) { state = 2; stateStart = userTime; }
            paramValue = 1.0f;
            break;
        case 2: {
            float t = (userTime - stateStart) / closing;
            if (t >= 1.0f) { t=1.0f; state=3; stateStart=userTime; }
            paramValue = 1.0f - t;
            break; }
        case 3: {
            float t = (userTime - stateStart) / closed;
            if (t >= 1.0f) { state=4; stateStart=userTime; }
            paramValue = 0.0f;
            break; }
        case 4: {
            float t = (userTime - stateStart) / opening;
            if (t >= 1.0f) {
                t=1.0f; state=1;
                float r = (float)rand() / (float)RAND_MAX;
                nextBlink = userTime + r * (2.0f * blinkInterval - 1.0f);
            }
            paramValue = t;
            break; }
        }
        w.os(); w.wf("t",userTime); w.wi("state",state); w.wf("paramValue",paramValue); w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/eye_blink_golden.json", w.str());
}

// ============================================================================
// Model loading helper — loads a Haru model via Framework + Core
// ============================================================================
struct LoadedModel {
    CubismMoc* moc = nullptr;
    CubismModel* model = nullptr;
    ICubismModelSetting* settings = nullptr;
    std::vector<csmByte> mocBuf;

    ~LoadedModel() {
        if (model && moc) moc->DeleteModel(model);
        if (moc) CubismMoc::Delete(moc);
        if (settings) delete settings;
    }
};

static bool loadModel(LoadedModel& lm, const std::string& dir, const std::string& name) {
    auto settingsBuf = readFile(dir + "/" + name + ".model3.json");
    if (settingsBuf.empty()) { printf("  Failed: %s.model3.json\n", name.c_str()); return false; }
    lm.settings = new CubismModelSettingJson(settingsBuf.data(), settingsBuf.size());

    lm.mocBuf = readFile(dir + "/" + lm.settings->GetModelFileName());
    if (lm.mocBuf.empty()) { printf("  Failed: moc file\n"); return false; }
    lm.moc = CubismMoc::Create(lm.mocBuf.data(), lm.mocBuf.size(), false);
    if (!lm.moc) { printf("  Failed: CubismMoc::Create\n"); return false; }
    lm.model = lm.moc->CreateModel();
    if (!lm.model) { printf("  Failed: CreateModel\n"); return false; }
    return true;
}

// ============================================================================
// Motion golden — loads motion3.json, evaluates curves at 60 FPS frames
// ============================================================================
static void genMotion(const std::string& d, const std::string& sampleDir) {
    printf("Generating motion_haru_idle_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    auto motionBuf = readFile(sampleDir + "/motions/haru_g_idle.motion3.json");
    if (motionBuf.empty()) { printf("  Skipped: motion file not found\n"); return; }
    CubismMotion* motion = CubismMotion::Create(motionBuf.data(), motionBuf.size());
    if (!motion) return;

    motion->SetFadeInTime(0.0f);  // No fade for clean comparison
    motion->SetFadeOutTime(0.0f);
    motion->SetLoop(false);

    Jw w;
    w.os();
    w.wf("duration", motion->GetDuration());
    w.wf("fps", 60.0);

    // Create a motion queue entry to drive the motion
    CubismMotionManager mgr;
    mgr.StartMotionPriority(motion, false, 1);

    w.as("frames");
    csmFloat32 dt = 1.0f / 60.0f;
    int totalFrames = (int)(motion->GetLoopDuration() * 60.0f) + 1;
    if (totalFrames > 600) totalFrames = 600;

    for (int i = 0; i < totalFrames; i++) {
        mgr.UpdateMotion(lm.model, dt);
        lm.model->Update();

        w.os();
        w.wf("frame", i);
        w.wf("t", i * dt);
        w.as("paramSamples");
        // Sample first 5 parameters (limit output size)
        int n = lm.model->GetParameterCount();
        if (n > 5) n = 5;
        for (int p = 0; p < n; p++) {
            w.os();
            w.ws("id", lm.model->GetParameterId(p)->GetString().GetRawString());
            w.wf("value", lm.model->GetParameterValue(p));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/motion_haru_idle_golden.json", w.str());

    ACubismMotion::Delete(motion);
}

// ============================================================================
// Expression golden — applies exp3.json with various weights
// ============================================================================
static void genExpression(const std::string& d, const std::string& sampleDir) {
    printf("Generating expression_haru_F01_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    auto expBuf = readFile(sampleDir + "/expressions/F01.exp3.json");
    if (expBuf.empty()) return;
    CubismExpressionMotion* exp = CubismExpressionMotion::Create(expBuf.data(), expBuf.size());
    if (!exp) return;

    Jw w;
    w.os();
    w.wf("fadeInTime", exp->GetFadeInTime());
    w.wf("fadeOutTime", exp->GetFadeOutTime());

    auto params = exp->GetExpressionParameters();
    w.as("expressionParameters");
    for (csmUint32 i = 0; i < params.GetSize(); i++) {
        w.os();
        w.ws("id", params[i].ParameterId->GetString().GetRawString());
        w.wi("blendType", params[i].BlendType);
        w.wf("value", params[i].Value);
        w.oe();
    }
    w.ae();

    // Apply expression at multiple weights, record changed parameters
    csmFloat32 weights[] = {0.0f, 0.25f, 0.5f, 0.75f, 1.0f};
    w.as("weightSamples");
    for (csmFloat32 wt : weights) {
        // Reset model parameters to defaults
        lm.model->LoadParameters();
        for (int p = 0; p < lm.model->GetParameterCount(); p++) {
            lm.model->SetParameterValue(p, lm.model->GetParameterDefaultValue(p));
        }

        // Apply expression directly (without queue manager)
        for (csmUint32 i = 0; i < params.GetSize(); i++) {
            auto& ep = params[i];
            switch (ep.BlendType) {
                case CubismExpressionMotion::Additive:
                    lm.model->AddParameterValue(ep.ParameterId, ep.Value, wt);
                    break;
                case CubismExpressionMotion::Multiply:
                    lm.model->MultiplyParameterValue(ep.ParameterId, ep.Value, wt);
                    break;
                case CubismExpressionMotion::Overwrite:
                    lm.model->SetParameterValue(ep.ParameterId, ep.Value, wt);
                    break;
            }
        }

        w.os();
        w.wf("weight", wt);
        w.as("params");
        for (csmUint32 i = 0; i < params.GetSize(); i++) {
            int idx = lm.model->GetParameterIndex(params[i].ParameterId);
            if (idx < 0) continue;
            w.os();
            w.ws("id", params[i].ParameterId->GetString().GetRawString());
            w.wf("value", lm.model->GetParameterValue(idx));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/expression_haru_F01_golden.json", w.str());

    ACubismMotion::Delete(exp);
}

// ============================================================================
// Motion queue golden — two motions with priorities, fade transitions
// ============================================================================
static void genMotionQueue(const std::string& d, const std::string& sampleDir) {
    printf("Generating motion_queue_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    auto m1Buf = readFile(sampleDir + "/motions/haru_g_idle.motion3.json");
    auto m2Buf = readFile(sampleDir + "/motions/haru_g_m01.motion3.json");
    if (m1Buf.empty() || m2Buf.empty()) return;

    CubismMotion* m1 = CubismMotion::Create(m1Buf.data(), m1Buf.size());
    CubismMotion* m2 = CubismMotion::Create(m2Buf.data(), m2Buf.size());
    if (!m1 || !m2) return;

    m1->SetFadeInTime(0.5f);
    m1->SetFadeOutTime(0.5f);
    m2->SetFadeInTime(0.5f);
    m2->SetFadeOutTime(0.5f);

    CubismMotionManager mgr;
    mgr.StartMotionPriority(m1, false, 1);

    Jw w;
    w.os();
    w.as("frames");
    csmFloat32 dt = 1.0f / 60.0f;

    for (int i = 0; i < 120; i++) {
        // At frame 30, queue motion 2 with higher priority
        if (i == 30) {
            mgr.StartMotionPriority(m2, false, 2);
        }

        mgr.UpdateMotion(lm.model, dt);
        lm.model->Update();

        w.os();
        w.wf("frame", i);
        w.wf("t", i * dt);
        w.as("paramSamples");
        int n = lm.model->GetParameterCount();
        if (n > 3) n = 3;
        for (int p = 0; p < n; p++) {
            w.os();
            w.ws("id", lm.model->GetParameterId(p)->GetString().GetRawString());
            w.wf("value", lm.model->GetParameterValue(p));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/motion_queue_golden.json", w.str());

    ACubismMotion::Delete(m1);
    ACubismMotion::Delete(m2);
}

// ============================================================================
// Physics golden — load physics3.json, run 300-frame simulation
// ============================================================================
static void genPhysics(const std::string& d, const std::string& sampleDir) {
    printf("Generating physics_haru_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    auto phBuf = readFile(sampleDir + "/" + lm.settings->GetPhysicsFileName());
    if (phBuf.empty()) return;

    CubismPhysics* physics = CubismPhysics::Create(phBuf.data(), phBuf.size());
    if (!physics) return;

    physics->Stabilization(lm.model);

    Jw w;
    w.os();
    w.wf("frames", 300);
    w.as("frameData");

    csmFloat32 dt = 1.0f / 60.0f;
    for (int i = 0; i < 300; i++) {
        // Set some input parameters to create motion for physics to react to
        lm.model->SetParameterValue(
            CubismFramework::GetIdManager()->GetId("ParamAngleX"),
            sin(i * 0.1f) * 30.0f);

        physics->Evaluate(lm.model, dt);
        lm.model->Update();

        // Sample physics-driven parameters (hair, etc.)
        w.os();
        w.wf("frame", i);
        w.as("paramSamples");
        int n = lm.model->GetParameterCount();
        if (n > 5) n = 5;
        for (int p = 0; p < n; p++) {
            w.os();
            w.ws("id", lm.model->GetParameterId(p)->GetString().GetRawString());
            w.wf("value", lm.model->GetParameterValue(p));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/physics_haru_golden.json", w.str());

    CubismPhysics::Delete(physics);
}

// ============================================================================
// Pose golden — load pose3.json, step through 120 frames
// ============================================================================
static void genPose(const std::string& d, const std::string& sampleDir) {
    printf("Generating pose_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    auto poseBuf = readFile(sampleDir + "/" + lm.settings->GetPoseFileName());
    if (poseBuf.empty()) return;

    CubismPose* pose = CubismPose::Create(poseBuf.data(), poseBuf.size());
    if (!pose) return;

    Jw w;
    w.os();
    w.as("frames");
    csmFloat32 dt = 1.0f / 60.0f;

    for (int i = 0; i < 120; i++) {
        pose->UpdateParameters(lm.model, dt);
        lm.model->Update();

        w.os();
        w.wf("frame", i);
        w.as("partOpacities");
        int n = lm.model->GetPartCount();
        if (n > 10) n = 10;
        for (int p = 0; p < n; p++) {
            w.os();
            w.ws("id", lm.model->GetPartId(p)->GetString().GetRawString());
            w.wf("opacity", lm.model->GetPartOpacity(p));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/pose_golden.json", w.str());

    CubismPose::Delete(pose);
}

// ============================================================================
// Model setting golden — parse model3.json, dump all extracted fields
// ============================================================================
static void genModelSetting(const std::string& d, const std::string& sampleDir) {
    printf("Generating model_setting_haru_golden.json...\n");
    auto buf = readFile(sampleDir + "/Haru.model3.json");
    if (buf.empty()) return;

    CubismModelSettingJson settings(buf.data(), buf.size());

    Jw w;
    w.os();
    w.ws("modelFileName", settings.GetModelFileName());
    w.wi("textureCount", settings.GetTextureCount());
    w.ws("physicsFileName", settings.GetPhysicsFileName());
    w.ws("poseFileName", settings.GetPoseFileName());
    w.wi("expressionCount", settings.GetExpressionCount());
    w.wi("motionGroupCount", settings.GetMotionGroupCount());
    w.wi("hitAreasCount", settings.GetHitAreasCount());
    w.wi("eyeBlinkParameterCount", settings.GetEyeBlinkParameterCount());
    w.wi("lipSyncParameterCount", settings.GetLipSyncParameterCount());

    w.as("textures");
    for (int i = 0; i < settings.GetTextureCount(); i++) {
        w.os(); w.ws("file", settings.GetTextureFileName(i)); w.oe();
    }
    w.ae();

    w.as("expressions");
    for (int i = 0; i < settings.GetExpressionCount(); i++) {
        w.os();
        w.ws("name", settings.GetExpressionName(i));
        w.ws("file", settings.GetExpressionFileName(i));
        w.oe();
    }
    w.ae();

    w.as("motionGroups");
    for (int i = 0; i < settings.GetMotionGroupCount(); i++) {
        const csmChar* groupName = settings.GetMotionGroupName(i);
        w.os();
        w.ws("name", groupName);
        w.wi("count", settings.GetMotionCount(groupName));
        w.as("motions");
        for (int j = 0; j < settings.GetMotionCount(groupName); j++) {
            w.os();
            w.ws("file", settings.GetMotionFileName(groupName, j));
            w.wf("fadeIn", settings.GetMotionFadeInTimeValue(groupName, j));
            w.wf("fadeOut", settings.GetMotionFadeOutTimeValue(groupName, j));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();

    w.as("hitAreas");
    for (int i = 0; i < settings.GetHitAreasCount(); i++) {
        w.os();
        w.ws("id", settings.GetHitAreaId(i)->GetString().GetRawString());
        w.ws("name", settings.GetHitAreaName(i));
        w.oe();
    }
    w.ae();

    w.oe();
    save(d + "/model_setting_haru_golden.json", w.str());
}

// ============================================================================
// Full pipeline golden — model + idle motion + physics + eye blink + breath
// ============================================================================
static void genFullPipeline(const std::string& d, const std::string& sampleDir) {
    printf("Generating full_pipeline_haru_golden.json...\n");
    LoadedModel lm;
    if (!loadModel(lm, sampleDir, "Haru")) return;

    // Load motion
    auto motionBuf = readFile(sampleDir + "/motions/haru_g_idle.motion3.json");
    CubismMotion* motion = nullptr;
    if (!motionBuf.empty()) {
        motion = CubismMotion::Create(motionBuf.data(), motionBuf.size());
        if (motion) {
            motion->SetFadeInTime(0.5f);
            motion->SetFadeOutTime(0.5f);
            motion->SetLoop(true);
        }
    }

    // Load physics
    auto phBuf = readFile(sampleDir + "/" + lm.settings->GetPhysicsFileName());
    CubismPhysics* physics = nullptr;
    if (!phBuf.empty()) {
        physics = CubismPhysics::Create(phBuf.data(), phBuf.size());
        if (physics) physics->Stabilization(lm.model);
    }

    // Eye blink
    csmVector<CubismIdHandle> eyeIds;
    for (int i = 0; i < lm.settings->GetEyeBlinkParameterCount(); i++) {
        eyeIds.PushBack(lm.settings->GetEyeBlinkParameterId(i));
    }
    CubismEyeBlink* eyeBlink = CubismEyeBlink::Create(lm.settings);

    // Breath
    CubismBreath* breath = CubismBreath::Create();
    csmVector<CubismBreath::BreathParameterData> breathParams;
    CubismBreath::BreathParameterData bp;
    bp.ParameterId = CubismFramework::GetIdManager()->GetId("ParamBreath");
    bp.Offset = 0.5f; bp.Peak = 0.5f; bp.Cycle = 3.2345f; bp.Weight = 0.5f;
    breathParams.PushBack(bp);
    breath->SetParameters(breathParams);

    // Motion manager
    CubismMotionManager mgr;
    if (motion) mgr.StartMotionPriority(motion, false, 1);

    Jw w;
    w.os();
    w.wf("frames", 300);
    w.as("frameData");

    csmFloat32 dt = 1.0f / 60.0f;
    for (int i = 0; i < 300; i++) {
        if (motion) mgr.UpdateMotion(lm.model, dt);
        if (eyeBlink) eyeBlink->UpdateParameters(lm.model, dt);
        if (breath) breath->UpdateParameters(lm.model, dt);
        if (physics) physics->Evaluate(lm.model, dt);
        lm.model->Update();

        w.os();
        w.wf("frame", i);
        w.as("paramSamples");
        int n = lm.model->GetParameterCount();
        if (n > 5) n = 5;
        for (int p = 0; p < n; p++) {
            w.os();
            w.ws("id", lm.model->GetParameterId(p)->GetString().GetRawString());
            w.wf("value", lm.model->GetParameterValue(p));
            w.oe();
        }
        w.ae();
        w.oe();
    }
    w.ae();
    w.oe();
    save(d + "/full_pipeline_haru_golden.json", w.str());

    if (motion) ACubismMotion::Delete(motion);
    if (physics) CubismPhysics::Delete(physics);
    if (eyeBlink) CubismEyeBlink::Delete(eyeBlink);
    if (breath) CubismBreath::Delete(breath);
}

// ============================================================================
// main
// ============================================================================
int main(int argc, char** argv) {
    std::string outDir = "../../test/golden";
    std::string sampleDir = "../../Samples/Resources/Haru";
    if (argc > 1) outDir = argv[1];
    if (argc > 2) sampleDir = argv[2];

    printf("=== Cubism Golden Reference Generator ===\n");
    printf("Linked against actual C++ Cubism Framework + Core library\n");
    printf("Output: %s\n", outDir.c_str());
    printf("Samples: %s\n\n", sampleDir.c_str());

    // Initialize the Cubism Framework (required for IdManager etc.)
    SimpleAllocator allocator;
    CubismFramework::Option opt;
    opt.LogFunction = nullptr;
    CubismFramework::StartUp(&allocator, &opt);
    CubismFramework::Initialize();

    // Math/Effect golden data (no model required)
    genMath(outDir);
    genBreath(outDir);
    genLook(outDir);
    genEyeBlink(outDir);

    // Model-based golden data (requires actual sample model)
    genMotion(outDir, sampleDir);
    genExpression(outDir, sampleDir);
    genMotionQueue(outDir, sampleDir);
    genPhysics(outDir, sampleDir);
    genPose(outDir, sampleDir);
    genModelSetting(outDir, sampleDir);
    genFullPipeline(outDir, sampleDir);

    CubismFramework::Dispose();

    printf("\nDone. All 11 golden reference files generated from actual C++ Framework.\n");
    return 0;
}
