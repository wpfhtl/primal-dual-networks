// Copyright (C) 2016 Gernot Riegler
// Institute for Computer Graphics and Vision (ICG)
// Graz University of Technology (TU GRAZ)

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. All advertising materials mentioning features or use of this software
//    must display the following acknowledgement:
//    This product includes software developed by the ICG, TU GRAZ.
// 4. Neither the name of the ICG, TU GRAZ nor the
//    names of its contributors may be used to endorse or promote products
//    derived from this software without specific prior written permission.

// THIS SOFTWARE IS PROVIDED ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE PROVIDER BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



#ifndef TH_GENERIC_FILE
#define TH_GENERIC_FILE "generic/IcgGeneralizedNablaT.c"
#else

static int icgnn_(IcgGeneralizedNablaT_updateOutput)(lua_State *L)
{
  THTensor* in = luaT_checkudata(L, 2, torch_Tensor);
  int neg = luaT_getfieldcheckboolean(L, 1, "neg");
  
  THTensor* dir = luaT_getfieldcheckudata(L, 1, "directions", torch_Tensor);
  THTensor* out = luaT_getfieldcheckudata(L, 1, "output", torch_Tensor);

  long n_dim = in->nDimension;
  luaL_argcheck(L, n_dim == 3 || n_dim == 4, 2, "3D or 4D(batch mode) tensor expected");

  in = THTensor_(newContiguous)(in);
  real* in_data = THTensor_(data)(in);

  real* dir_data = THTensor_(data)(dir);
  long n_dir = dir->size[1];

  long num, channels, height, width, out_channels;
  if(n_dim == 3) {
    num = 1;
    channels = in->size[0];
    height = in->size[1];
    width = in->size[2];
    out_channels = channels / n_dir;
    THTensor_(resize3d)(out, out_channels, height, width);
  }
  else if(n_dim == 4) {
    num = in->size[0];
    channels = in->size[1];
    height = in->size[2];
    width = in->size[3];
    out_channels = channels / n_dir;
    THTensor_(resize4d)(out, num, out_channels, height, width);  
  }
  luaL_argcheck(L, channels % n_dir == 0, 2, "input channels % 2 != 0");

  real* out_data = THTensor_(data)(out);

  long offset = height * width;
  long n;
#pragma omp parallel for private(n)
  for(n = 0; n < num; ++n) {
    long c;
    for(c = 0; c < channels; c += n_dir) {
      long h;
      for(h = 0; h < height; ++h) {
        long w;
        for(w = 0; w < width; ++w) {
          long out_idx = ((n * out_channels + c/n_dir) * height + h) * width + w;
          out_data[out_idx] = 0;

          int dir_idx = 0;
          for(dir_idx = 0; dir_idx < n_dir; ++dir_idx) {
            // minus (-) dir data, because it has to be inv to GeneralizedNabla
            long dir_x = -dir_data[dir_idx];
            long dir_y = -dir_data[n_dir + dir_idx];

            long in_idx = ((n * channels + c+dir_idx) * height + h) * width + w;
          
            if(w+dir_x >= 0 && h+dir_y >= 0 && w+dir_x < width && h+dir_y < height) {
              out_data[out_idx] += in_data[in_idx + dir_y * width + dir_x];
            }
            if(w-dir_x >= 0 && h-dir_y >= 0 && w-dir_x < width && h-dir_y < height) {
              out_data[out_idx] -= in_data[in_idx];
            }
          }

          if(neg) {
            out_data[out_idx] = -out_data[out_idx];
          }
        }
      }
    }
  }
  
  THTensor_(free)(in);

  return 1;
}

static int icgnn_(IcgGeneralizedNablaT_updateGradInput)(lua_State *L)
{
  THTensor *in = luaT_checkudata(L, 2, torch_Tensor);
  THTensor *grad_out = luaT_checkudata(L, 3, torch_Tensor);
  int neg = luaT_getfieldcheckboolean(L, 1, "neg");

  THTensor* dir = luaT_getfieldcheckudata(L, 1, "directions", torch_Tensor);
  THTensor *out = luaT_getfieldcheckudata(L, 1, "output", torch_Tensor);
  THTensor *grad_in = luaT_getfieldcheckudata(L, 1, "gradInput", torch_Tensor);

  THTensor_(resizeAs)(grad_in, in);
  
  real* in_data = THTensor_(data)(in);
  real* out_data = THTensor_(data)(out);
  real* grad_in_data = THTensor_(data)(grad_in);
  real* grad_out_data = THTensor_(data)(grad_out);

  real* dir_data = THTensor_(data)(dir);
  long n_dir = dir->size[1];
  
  long n_dim = in->nDimension;
  long num, channels, height, width, out_channels;
  if(n_dim == 3) {
    num = 1;
    channels = in->size[0];
    height = in->size[1];
    width = in->size[2];
    out_channels = channels / n_dir;
  }
  else if(n_dim == 4) {
    num = in->size[0];
    channels = in->size[1];
    height = in->size[2];
    width = in->size[3];
    out_channels = channels / n_dir;
  }

  THTensor_(zero)(grad_in);
  neg = neg ? -1 : 1;
    
  long offset = height * width;
  long n;
#pragma omp parallel for private(n)
  for(n = 0; n < num; ++n) {
    long c;
    for(c = 0; c < channels; c += n_dir) {
      long h;
      for(h = 0; h < height; ++h) {
        long w;
        for(w = 0; w < width; ++w) {
          long out_idx = ((n * out_channels + c/n_dir) * height + h) * width + w;

          int dir_idx = 0;
          for(dir_idx = 0; dir_idx < n_dir; ++dir_idx) {
            // minus (-) dir data, because it has to be inv to GeneralizedNabla
            long dir_x = -dir_data[dir_idx];
            long dir_y = -dir_data[n_dir + dir_idx];

            long in_idx = ((n * channels + c+dir_idx) * height + h) * width + w;
          
            if(w+dir_x >= 0 && h+dir_y >= 0 && w+dir_x < width && h+dir_y < height) {
              grad_in_data[in_idx + dir_y * width + dir_x] += neg * grad_out_data[out_idx];
            }
            if(w-dir_x >= 0 && h-dir_y >= 0 && w-dir_x < width && h-dir_y < height) {
              grad_in_data[in_idx] += -neg * grad_out_data[out_idx];
            }
          }
        }
      }
    }
  }
  
  return 1;
}

static const struct luaL_Reg icgnn_(IcgGeneralizedNablaT__) [] = {
  {"IcgGeneralizedNablaT_updateOutput", icgnn_(IcgGeneralizedNablaT_updateOutput)},
  {"IcgGeneralizedNablaT_updateGradInput", icgnn_(IcgGeneralizedNablaT_updateGradInput)},
  {NULL, NULL}
};

static void icgnn_(IcgGeneralizedNablaT_init)(lua_State *L)
{
  luaT_pushmetatable(L, torch_Tensor);
  luaT_registeratname(L, icgnn_(IcgGeneralizedNablaT__), "icgnn");
  lua_pop(L,1);
}

#endif
