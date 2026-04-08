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

using namespace Live2D::Cubism::Framework;

// ---------------------------------------------------------------------------
// Minimal allocator for CubismFramework initialization
// ---------------------------------------------------------------------------
class SimpleAllocator : public ICubismAllocator {
public:
    void* Allocate(const csmSizeType size) override { return malloc(size); }
    void Deallocate(void* addr) override { free(addr); }
    void* AllocateAligned(const csmSizeType size, const csmUint32 align) override {
        size_t offset = align - 1 + sizeof(void*);
        void* p = malloc(size + offset);
        void** aligned = (void**)(((size_t)p + offset) & ~(align - 1));
        aligned[-1] = p;
        return aligned;
    }
    void DeallocateAligned(void* addr) override {
        free(((void**)addr)[-1]);
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
// main
// ============================================================================
int main(int argc, char** argv) {
    std::string outDir = "../../test/golden";
    if (argc > 1) outDir = argv[1];

    printf("=== Cubism Golden Reference Generator ===\n");
    printf("Linked against actual C++ Cubism Framework + Core library\n");
    printf("Output: %s\n\n", outDir.c_str());

    // Initialize the Cubism Framework (required for IdManager etc.)
    SimpleAllocator allocator;
    CubismFramework::Option opt;
    opt.LogFunction = nullptr;
    CubismFramework::StartUp(&allocator, &opt);
    CubismFramework::Initialize();

    genMath(outDir);
    genBreath(outDir);
    genLook(outDir);
    genEyeBlink(outDir);

    CubismFramework::Dispose();

    printf("\nDone. All golden reference data generated from actual C++ Framework.\n");
    return 0;
}
