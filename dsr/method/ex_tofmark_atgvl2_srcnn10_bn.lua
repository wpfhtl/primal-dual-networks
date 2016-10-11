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
opt.ex_method = 'atgvl2_srcnn10_bn'
opt.ex_dataset = 'tofmark'
opt.experiment_name = opt.ex_dataset..'_'..opt.ex_method
opt.cudnn = true
opt.train_gpu = true
opt.test_gpu = true
opt.scale = 1
opt.input_datasets = {'in_depth'}
opt.target_datasets = {'ta_depth'}
opt.mask_datasets = {'mask'}
opt.net_model = 'models/srcnn10_atgvl2.lua'
opt.momentum = 0.9
opt.epoch = 5
opt.learningRate_step = 30
opt.learningRate_factor = 0.1
opt.save_interval = 1
opt.narrow = 10

opt.ex_root = paths.concat(opt.data_root, opt.experiment_name)
print('ex_root: '..opt.ex_root)
paths.mkdir(opt.ex_root)
opt.out_prefix = paths.concat(opt.ex_root, 'out')
opt.image_names = {{'Books'}, {'Devil'}, {'Shark'}}

opt.init_net_weights_path = paths.concat(opt.data_root, 'tofmark_srcnn10_bn/weights_epoch30.t7')
opt.atgvl2_params = {10, 0.01, 0.01, 17, 1.2, 9, 0.85}

opt.train_input_h5_paths = icgnn.listH5(opt.data_root, 'tofmark/ph152_pw202_train_n')
opt.test_input_h5_paths = icgnn.listH5(opt.data_root, 'tofmark/tofmark')

-- log training
local log_path = paths.concat(opt.ex_root, 'run.log')
print('log to '..log_path)
local cmd = torch.CmdLine()
cmd:log(log_path, params)
for k, v in pairs(opt) do print(string.format('opt.%s = %s', k, v)) end


-- target net
local target = nn.Identity()()   
local target_data_net = nn.gModule({target}, {icgnn.IcgNarrow(opt.narrow)(target)})
target_data_net:cuda()
opt.target_data_preprocess_fcn = function(x) return target_data_net:forward(x) end

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

-- load model
local model = require(opt.net_model)
opt = model.load(opt)
opt.batch_size = 24



-- test if weights already exist, otherwise train network
local last_net_weights_path = paths.concat(opt.ex_root, 'weights_epoch'..opt.epoch..'.t7')
if paths.filep(last_net_weights_path) and false then
  opt.net = torch.load(last_net_weights_path)

  print('test network')
  opt.ex_run = opt.epoch + 1
  icgnn.test(opt)
else
  print('test epoch init')
  opt.ex_run = 0
  icgnn.test(opt)   

  for epoch = 1, opt.epoch do
    print('epoch #' .. epoch .. ' of ' .. opt.epoch .. ' | lr = ' .. opt.learningRate)
    local tim = torch.Timer()
    icgnn.train(opt)
    print('epoch #'..epoch..' took '..tim:time().real..'[s]')

    print('test after train epoch '..epoch)
    opt.ex_run = epoch
    icgnn.test(opt)   

    -- save latest network
    if epoch % opt.save_interval == 0 or (epoch == opt.epoch) then
      local net_weights_path = paths.concat(opt.ex_root, 'weights_epoch'..epoch..'.t7')
      icgnn.saveNetWeights(net_weights_path, opt.net)
      print('saved model to: ' .. net_weights_path)
    end  

    -- adjust lr
    if epoch % opt.learningRate_step == 0 then 
      opt.learningRate = opt.learningRate * opt.learningRate_factor 
    end
  end 
end
