// Stub for CubismRenderer::StaticRelease() which is called by
// CubismFramework::Dispose(). The golden generator doesn't use rendering,
// but the Framework links against this symbol.
#include "Rendering/CubismRenderer.hpp"

namespace Live2D { namespace Cubism { namespace Framework { namespace Rendering {
void CubismRenderer::StaticRelease() {}
}}}}
