#!/usr/bin/env th

-- Copyright (C) 2016 Gernot Riegler
-- Institute for Computer Graphics and Vision (ICG)
-- Graz University of Technology (TU GRAZ)

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. All advertising materials mentioning features or use of this software
--    must display the following acknowledgement:
--    This product includes software developed by the ICG, TU GRAZ.
-- 4. Neither the name of the ICG, TU GRAZ nor the
--    names of its contributors may be used to endorse or promote products
--    derived from this software without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED ''AS IS'' AND ANY
-- EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL THE PROVIDER BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require('settings')


-- settings
opt.ex_db_path = paths.concat(opt.data_root, 'experiments.db')
opt.ex_method = 'blcl_de124_srcnn15'
opt.scale = 1
opt.ex_dataset = 'tm'
opt.experiment_name = opt.ex_dataset..'_'..opt.ex_method
opt.cudnn = true
opt.train_gpu = true
opt.test_gpu = true
opt.train_input_datasets = {'depth_mr_bl', 'rgb'}
opt.train_target_datasets = {'depth'}
opt.test_input_datasets = {'depth_mr_bl', 'rgb'}
opt.test_target_datasets = {'depth_hr'}
opt.net_model = 'models/dc_de124_srcnn15.lua'
opt.batch_size = 128
opt.momentum = 0.9
opt.epoch = 30
opt.learningRate_steps = {}
opt.learningRate_steps[15] = 0.5
opt.learningRate_steps[20] = 0.2
opt.save_interval = 1

opt.train_input_h5_paths = icgnn.listH5(opt.data_root, 'data_rendering/patches/tm48/ph48_pw48')
opt.test_input_h5_paths = icgnn.listH5(opt.data_root, 'test_data/tofmark/tofmark')

opt.ex_root = paths.concat(opt.data_root, 'train', opt.experiment_name)
print('ex_root: '..opt.ex_root)
paths.mkdir(opt.ex_root)
opt.out_prefix = paths.concat(opt.ex_root, 'out')
opt.image_names = {{'Books'}, {'Devil'}, {'Shark'}}

-- log training
local cmd = torch.CmdLine()
cmd:option('-mode', '', 'train/train_test/test_all/test_latest')
local cmd_args = cmd:parse(arg)

local log_path = paths.concat(opt.ex_root, 'run_'..cmd_args['mode']..'.log')
cmd:log(log_path, params)
print('log to '..log_path)
for k, v in pairs(opt) do print(string.format('opt.%s = %s', k, v)) end


-- load model 
local model = require(opt.net_model)
opt = model.load(opt)

-- target net
local gen_nabla = torch.zeros(2, 24)
local idx = 1
for x = -3, 3 do 
  for y = -3, 0 do 
    if x >= 0 and y == 0 then break end
    gen_nabla[1][idx] = x
    gen_nabla[2][idx] = y
    idx = idx + 1
  end
end 
print(gen_nabla)

local target = nn.Identity()()   
local target_e = icgnn.IcgGeneralizedNabla(gen_nabla)(target)
opt.target_data_net = nn.gModule({target}, {icgnn.IcgNarrow(opt.narrow)(target), icgnn.IcgNarrow(opt.narrow)(target_e)})
opt.target_data_preprocess_fcn = function(x) return opt.target_data_net:forward(x) end

-- set up metrics
opt.metrics = {}
opt.metrics['rmse'] = function (input, target) 
  input = input:clone()
  target = target:clone()
  input[torch.lt(target, 0)] = -1
  target[torch.lt(target, 0)] = -1
  return math.sqrt(torch.pow(input - target, 2):sum() / torch.ge(target, 0):sum())
end
opt.metrics['sad'] = function (input, target) 
  input = input:clone()
  target = target:clone()
  input[torch.lt(target, 0)] = -1
  target[torch.lt(target, 0)] = -1
  return torch.abs(input - target):sum() / torch.ge(target, 0):sum()
end


if cmd_args['mode'] == 'test_all' or cmd_args['mode'] == 'test_latest' then
  for epoch = opt.epoch, 1, -1 do
    local net_path = paths.concat(opt.ex_root, 'net_epoch'..epoch..'.t7')
    if paths.filep(net_path) then 
      print('test network epoch '..epoch)
      opt.net = torch.load(net_path)
      opt.ex_run = epoch
      icgnn.test(opt)
      
      if cmd_args['mode'] == 'test_latest' then break end
    end
  end 
elseif cmd_args['mode'] == 'train' or cmd_args['mode'] == 'train_test' then
  print('test epoch init')
  opt.ex_run = 0
  if cmd_args['mode'] == 'train_test' then icgnn.test(opt) end

  for epoch = 1, opt.epoch do
    print('epoch #' .. epoch .. ' of ' .. opt.epoch .. ' | lr = ' .. opt.learningRate)
    local tim = torch.Timer()
    icgnn.train(opt)
    print('epoch #'..epoch..' took '..tim:time().real..'[s]')

    print('test after train epoch '..epoch)
    opt.ex_run = epoch
    if cmd_args['mode'] == 'train_test' then icgnn.test(opt) end

    -- save latest network
    if epoch % opt.save_interval == 0 or (epoch == opt.epoch) then
      local net_path = paths.concat(opt.ex_root, 'net_epoch'..epoch..'.t7')
      torch.save(net_path, opt.net:clearState())
      print('saved model to: ' .. net_path)
    end  

    -- adjust lr
    if opt.learningRate_steps[epoch] ~= nil then
      opt.learningRate = opt.learningRate * opt.learningRate_steps[epoch]
    end
  end 
else 
  error('unknown mode: '..cmd_args['mode'])
end


