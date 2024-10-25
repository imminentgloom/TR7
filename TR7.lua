-- [tbd]
-- 
-- 
--
-- 
--
--
-- v0.7 imminent gloom


-- wtf am i working on now?
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- get jum step jump working
-- only randomize track that have rec enabled
-- set edit step when we randomize
-- make some kind of screen interface
-- find name!!!


-- setup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local g = grid.connect()

tab = require("tabutil")

nb = include("lib/nb")

local save_on_exit = true

t = {} -- hold tracks

local p = { -- holds patterns
   data = {
      {{},{},{},{}},
      {{},{},{},{}},
      {{},{},{},{}},
      {{},{},{},{}},
   },
   data_step = {
      {{},{},{},{}},
      {{},{},{},{}},
      {{},{},{},{}},
      {{},{},{},{}},
   },
   active_steps = {{},{},{},{}},
   state = {"empty", "empty", "empty", "empty"},
   current = 1,
}

local edit = {
   track = 1,
   step = 1
}

local active_steps = {}

local trig = {false, false, false, false}
local trig_index = {1, 1, 1, 1}
local mute = {false, false, false, false}
local rec = {true, true, true, true}
local erase = false
local select = false
local shift_1 = false
local shift_2 = false
local retrigger

local seq_play = true
local halt_step
local seq_reset = false

local loop_buff = {{},{},{},{},{}}
local fill_buff = {}
local shift_buff_1 = {}
local shift_buff_2 = {}

local fill_rate = {1, 2, 4, 8, 12, 24}

local ppqn = 96

local fps = 32
local frame = 1
local frame_anim = 1
local frames = 8
local frame_rnd_step = 1

local trig_pulled = {false, false, false, false}

local k1_held = false

local crow_trig = true

-- Track class
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

track = {}
track.__index = track
track.substeps = ppqn / 4

local num_tracks = 0

function track.new()
   local sequence = setmetatable({}, track)
   
   num_tracks = num_tracks + 1
   sequence.number = num_tracks
   
   sequence.voice = "nb_voice_" .. num_tracks
   nb:add_param(tostring(sequence.voice), "track " .. num_tracks .. ":" )
   
   sequence.index = 1
   sequence.step = 1
   sequence.substep = 1

   sequence.forward = true

   sequence.loop_start = 1
   sequence.loop_end = 16

   sequence.note = sequence.number
   sequence.velocity = 1
   sequence.duration = 1

   sequence.data = {}
   for n = 1, 16 * sequence.substeps do
      sequence.data[n] = 0
   end
   
   sequence.data_step = {}
   for n = 1, 16 do
      sequence.data_step[n] = 0
   end

   return sequence
end

-- step through sequence
function track:inc()
   self.index = self.index + 1
   if self.index >= self:step_2_index(self.loop_end) + self.substeps then
      self.index = self:step_2_index(self.loop_start)
   end

   if self.index < self:step_2_index(self.loop_start) then
      self.index = self:step_2_index(self.loop_start)
   end
   
   self.substep = math.floor(((self.index - 1) % self.substeps) + 1)
   
   self.step = self:index_2_step(self.index)
end

-- step back through sequence
function track:dec()
   self.index = self.index - 1
   if self.index <= self:step_2_index(self.loop_start) then
      self.index = self:step_2_index(self.loop_end) + self.substeps - 1
   end
   
   if self.index >= self:step_2_index(self.loop_end) + self.substeps then
      self.index = self:step_2_index(self.loop_end) + self.substeps
   end

   self.substep = math.floor(((self.index - 1) % self.substeps) + 1)

   self.step = self:index_2_step(self.index)
end

-- writes value to index OR value to current possition OR inverts current index
function track:write(val, index)
   local track = self.number
   index = index or self.index
   val = val or self.data[index] % 2
   
   -- write data
   self.data[index] = val

   -- add 16ths
   if val == 1 then
      self.data_step[self:index_2_step(index)] = 1
   end
   
   -- remove 16ths
   if val == 0 then
      if not self:get_step(self:index_2_step(index)) then 
         self.data_step[self:index_2_step(index)] = 0
      end
   end
   
   -- add active steps
   if val == 1 then
      table.insert(active_steps, {track = track, index = index})
   end
   
   -- remove active steps
   if val == 0 then
      for i , v in ipairs(active_steps) do
         if v.track == track and v.index == index then
            table.remove(active_steps, i)
            break
         end
      end
   end
end

-- resets to step OR start of loop
function track:reset(step)
   if self.forward then 
      step = step or 1
   end

   if not self.forward then
      step = step or 16
   end

   self.step = util.clamp(step, self.loop_start, self.loop_end)
   
   if self.forward then
      self.substep = 1
      self.index = self:step_2_index(self.step)
   end

   if not self.forward then
      self.substep = self.substeps
      self.index = self:step_2_index(self.step) + self.substeps
   end
end

-- sets loop points, args in any order
function track:loop(l1, l2)
   l1 = l1 or 1
   l2 = l2 or 16
   self.loop_start = math.min(l1, l2)
   self.loop_end = math.max(l1, l2)   
end

-- clear entire sequence
function track:clear_sequence()
   for index = 1, 16 * self.substeps do
      self:write(0, index)
   end
   for n = 1, #active_steps do
      active_steps[n] = nil
   end
end

-- clear step OR clear current step
function track:clear_step(step)
   step = step or self.step

   for step_num = self:step_2_index(step), self:step_2_index(step) + 23 do
      self:write(0, step_num)
   end   
end

-- trigger drum hit
function track:hit()
   player = params:lookup_param(self.voice):get_player()
   player:play_note(self.note, self.velocity, self.duration)
   
   if crow_trig then
      crow.output[self.number].action = "pulse()"
      crow.output[self.number]()
   end
end

-- converts step# to index
function track:step_2_index(step)
   return math.floor((step - 1) * self.substeps + 1)
end

-- converts index to step#
function track:index_2_step(index)
   return math.floor((index - 1) / 24) + 1
end

-- cheks if step has active substeps OR current step has active
function track:get_step(step)
   step = step or self.step
   local state = nil

   for substep = 1, self.substeps do
      if self.data[(step - 1) * self.substeps + substep] == 1 then
         state = true
         break
      end
   end
   return state or false
end

-- utility functions
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- tracks held keys in order
local function g_buffer(buff, val, z)
   if z == 1 then
      -- add all held fills to a table in order
      table.insert(buff, val)
   else
      -- remove each step as it is released
      for i, v in pairs(buff) do
         if v == val then
            table.remove(buff, i)
         end
      end
   end
end

-- pattern, load
local function pattern_to_sequence(pattern)
   for track = 1, 4 do
      for index = 1, ppqn * 4 do
         t[track].data[index] = p.data[pattern][track][index]
      end

      for step = 1, 16 do
         t[track].data_step[step] = p.data_step[pattern][track][step]
      end
   end

   for n = 1, #active_steps do
      active_steps[n] = nil
   end   

   for n = 1, #p.active_steps[pattern] do
      active_steps[n] = p.active_steps[pattern][n]
   end
   
   p.current = pattern
end

-- pattern, save
local function sequence_to_pattern(pattern)
   for track = 1, 4 do
      for index = 1, ppqn * 4 do
         p.data[pattern][track][index] = t[track].data[index]
      end

      for step = 1, 16 do
         p.data_step[pattern][track][step] = t[track].data_step[step]
      end
   end

   for n = 1, #p.active_steps[pattern] do
      p.active_steps[pattern][n] = nil
   end   

   for n = 1, #active_steps do
      p.active_steps[pattern][n] = active_steps[n]
   end

   p.state[pattern] = "full"
end

-- pattern, clear
local function pattern_clear(pattern)
   for track = 1, 4 do
      for index = 1, ppqn * 4 do
         p.data[pattern][track][index] = 0
      end

      for step = 1, 16 do
         p.data_step[pattern][track][step] = 0
      end
   end
   
   for n = 1, #p.active_steps[pattern] do
      p.active_steps[pattern][n] = nil
   end   

   p.state[pattern] = "empty"
end

-- init
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function init()
   
   nb.voice_count = 4

   for n = 1, 4 do t[n] = track.new() end
   
   nb:add_player_params()
   
   for pattern = 1, 4 do
      pattern_clear(pattern)
   end

   clk_main = clock.run(c_main)
   clk_fps = clock.run(c_fps)

   if save_on_exit then
      params:read("/home/we/dust/data/drumseq/drumseq_state.pset")
   end

   -- params
   -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
   params:add_option("crow", "crow triggers", {"on", "off"}, 1)
   params:set_action("crow", function(x) if x == 1 then crow_trig = true else crow_trig = false end end)
   -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

   g_redraw()

end

-- clock
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function c_main()
   while true do
      clock.sync(1/ppqn)
      
      for track = 1, 4 do
         if t[track].forward then
            t[track]:inc()
            c_main_core(track)			
         end

         if not t[track].forward then
            c_main_core(track)
            t[track]:dec()
         end
      end

      g_blink_triggers()
      
      if t[1].substep == 1 then -- because drawing 384 times/second @ 60 bpm is apparently stupid
         g_redraw()
      end

   end
end

function c_main_core(track)
   
   if erase and trig[track] then -- erase steps
      t[track]:write(0)
   end
   
   if retrigger then -- retrigger step
      if t[track].substep == 1 then
         t[track]:reset(loop_buff[5][1] or t[track].step)
      end
   end
   
   if fill and trig[track] then -- fill steps
      local rate = ppqn / 4 / fill_rate[util.clamp(#fill_buff, 0, #fill_rate)]
      
      if ((t[track].substep - 1) % rate) + 1 == ((trig_index[track] - 1) % rate) + 1 then
         if rec[track] then
            t[track]:write(1)
         end
         
         if not rec[track] and not mute[track] then
            t[track]:hit()                  
         end
      end
   end
   
   if t[track].data[t[track].index] == 1 and not mute[track] then -- trigger hit if not muted
      t[track]:hit()
   end	
end

function c_fps()
   while true do
      clock.sleep(1/fps)
      frame = frame + 1
      if frame > fps then
         frame = 1
      end
      frame_anim = util.clamp(math.floor(frames / fps * frame), 1, frames)
      frame_rnd = math.random(frames)
      g_redraw()
   end
end

-- grid: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function g.key(x, y, z)
   
   local row = y
   local col = x

   -- shift 1 and 2
   if row == 8 and col >=6 and col <=8 then
      g_buffer(shift_buff_1, col, z)
   end
    
   if row == 8 and col >=9 and col <=11 then
      g_buffer(shift_buff_2, col, z)

      if erase then
         for n = 1, 4 do
            t[n]:clear_sequence()
         end
      end
   end

   if #shift_buff_1 > 0 then shift_1 = true else shift_1 = false end
   if #shift_buff_2 > 0 then shift_2 = true else shift_2 = false end
   
   -- sequence
   if row <= 4 then

      if z == 1 then
         
         edit.track = y
         edit.step = x
         
         if select then
            edit.track = y
            edit.step = x
         end

         if not shift_1 and not select then
            if t[row]:get_step(col) then
               t[row]:clear_step(col)
            else
               t[row]:write(1, t[row]:step_2_index(col))
            end
         end
         
         if erase then
            t[row]:clear_step(col)
         end
      end
   end
   
   -- loop and retrigger
   if row == 1 then g_buffer(loop_buff[1], col, z) end
   if row == 2 then g_buffer(loop_buff[2], col, z) end
   if row == 3 then g_buffer(loop_buff[3], col, z) end
   if row == 4 then g_buffer(loop_buff[4], col, z) end
   if row <= 4 then g_buffer(loop_buff[5], col, z) end

   if #shift_buff_1 == 1 then -- retrigger step
      retrigger = true
   end

   if #shift_buff_1 ~= 1 then
      retrigger = false
   end

   if #shift_buff_1 == 2 then -- loop single track
      if row <= 4 then
         if #loop_buff[row] > 1 then
            t[row]:loop(loop_buff[row][1], loop_buff[5][#loop_buff[5]])
         end
      end
   end
      
   if #shift_buff_1 == 3 then -- loop all tracks
      if #loop_buff[5] > 1 then
         for track = 1, 4 do
            t[track]:loop(loop_buff[5][1], loop_buff[5][#loop_buff[5]])
         end
      end
   end
      
   if shift_1 and erase then -- release loops
      if #shift_buff_1 == 1 then
         for track = 1, 4 do
            t[track]:loop(1, 16)
         end
      else
         for track = 1, 4 do
            t[track]:loop(1, 16)
            t[track]:reset()
         end
      end
   end

   -- rec
   if row == 5 and col <= 4 then
      if z == 1 then
         if rec[col] then
            rec[col] = false
         else
            rec[col] = true
         end
      end   
   end
   
   -- mutes
   if row == 6 and col <= 4 then
      if z == 1 then
         if mute[col] then
            mute[col] = false
         else
            mute[col] = true
         end
      end
   end   

   -- triggers
   if row >= 7 and col <= 4 then
      if z == 1 then
         edit.track = col
         edit.step = t[col].step
         trig_index[col] = t[col].substep
         trig[col] = true
      end

      if z == 0 then
         trig[col] = false
         trig_index[col] = 1
      end
      
      if erase then
         t[col]:write(0)
      end

      if not mute[col] and not erase then
         if z == 1 and rec[col] then
            t[col]:write(1)
            t[col]:hit()
         end
         
         if z == 1 and not rec[col] then
            t[col]:hit()
         end
      end

   end
   
   -- patterns
   do
      local pattern_number = col - 12

      if row == 5 and col >= 13 then
         if z == 1 then pattern = true else pattern = false end
      end

      if pattern and erase then 	
         pattern_clear(pattern_number)
      end

      if pattern and shift_2 then
         sequence_to_pattern(pattern_number)
      end
      
      if pattern then
         pattern_to_sequence(pattern_number)
      end
   end

   -- erase
   if row == 6 and col == 16 then
      if z == 1 then erase = true else erase = false end	
   end

   if erase and shift_2 then
      for track = 1, 4 do
         if rec[track] then
            t[track]:clear_sequence()
         end
      end
   end
   
   -- select
   if row == 6 and col == 15 then
      if z == 1 then select = true else select = false end
   end

   -- reset
   if row == 6 and col == 14 then
      if z == 1 then seq_reset = true else seq_reset = false end
      
      if z == 1 then
         for track = 1, 4 do
            t[track]:reset()
         end
      end
   halt_step = 1
   end
   
   -- play
   if row == 6 and col == 13 then
      if z == 1 then
         if shift_2 then
            for track = 1, 4 do
               if t[track].forward then t[track].forward = false else t[track].forward = true end
            end
         end

         if not shift_2 then
            if seq_play then
               clock.cancel(clk_main)
               seq_play = false
            else
               clk_main = clock.run(c_main)
               seq_play = true
            end
         end
      end
   end   

   -- fill
   if (row == 7 or row == 8) and col >= 13 then
      local col = ((row - 7) * 4) + col - 12 
      g_buffer(fill_buff, col, z)
      if #fill_buff > 0 then fill = true else fill = false end
   end      
   
   -- step edit
   if (row == 5 or row == 6 or row == 7) and (col >=5 and col <= 12) then
      if z == 1 then
         local step = t[edit.track]:step_2_index(edit.step)
         local substep = (col - 4) + ((row - 5) * 8)

         if t[edit.track].data[step + substep - 1] == 1 then
            t[edit.track]:write(0, step + substep - 1)
         else
            t[edit.track]:write(1, step + substep - 1)
         end
      end
   end

   g_redraw()
   
end

-- grid: "color" palette
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local br_seq_l			=  4	-- sequence, looping steps
local br_seq_a			= 12	-- sequence, active steps
local br_seq_t			= 15	-- sequence, tracer
local br_seq_mod		=  1	-- sequence, mod
local br_sub			=  2	-- substeps, background
local br_sub_a			= 10	-- substeps, active steps
local br_sub_t			=  5	-- substeps, tracer
local br_rec			=  1	-- record
local br_m				=  8	-- mute
local br_t				=  4	-- triggers
local br_t_a			= 10	-- triggers, active steps
local br_t_h			= 15	--	triggers, held
local br_t_mod 		=  2	-- triggers, mod
local br_shift_1		=  5	-- shift 1
local br_shift_2		=  5	-- shift 2
local br_pat_e			=  0	-- pattern, empty
local br_pat_f			=  8	-- pattern, full
local br_pat_c			=  4	-- pattern, current, empty
local br_pat_c_f		= 12	-- pattern, current, full
local br_pat_mod 		=  2	-- pattern, mod
local br_e				=  8	-- erase
local br_e_a			=  2	-- erase, active
local br_e_mod			=  2	-- eaase, mode
local br_sel         =  4  -- select step
local br_sel_a       =  8  -- select step, active
local br_sel_mod	   =  4	-- select step, mod
local br_reset			=  8	-- reset
local br_reset_a		= 10	-- reset, active
local br_play			=  4	-- play
local br_play_a		= 10	-- play, active
local br_fill			=  4	-- fill
local br_fill_a		=  5	-- fill, active

local br_t_val       = {0, 0, 0, 0}  -- triggers, value
local br_t_val_prev  = {0, 0, 0, 0}  -- triggers, previous value

-- grid: lights
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function g_redraw()

   g:all(0)

   -- loop
   for y = 1, 4 do
      for x = t[y].loop_start, t[y].loop_end do
         if shift_1 then
            g:led(x, y, br_seq_l + br_seq_mod)
         else
            g:led(x, y, br_seq_l)
         end
      end
   end

   -- sequence
   for y = 1, 4 do
      for x = 1, 16 do
         if t[y].data_step[x] == 1 then
            if erase then
               g:led(x, y, br_seq_a - br_e_mod)
            else
               g:led(x, y, br_seq_a)
            end
         end
      end
   end

   -- track controls
   for x = 1, 4 do
      -- rec
      if rec[x] then g:led(x, 5, br_rec + frame_anim) end
      if not rec[x] then g:led(x, 5, 0) end

      -- mute
      if mute[x] then g:led(x, 6, br_m) end
      if not mute[x] then g:led(x, 6, 0) end
   end
   
   -- triggers
   for x = 1, 4 do
      if trig[x] then
         br_t_val[x] = br_t_h
      end

      if not trig[x] then
         br_t_val[x] = br_t
      end
      
      if mute[x] then
         br_t_val[x] = 0
      end
      
      if fill and not mute[x] then 
         br_t_val[x] = br_t + br_t_mod
      end

      g:led(x, 7, br_t_val[x])
      g:led(x, 8, br_t_val[x])
   end

   -- shift_1
   for x = 6, 8 do
      if shift_1 then
         g:led(x, 8, br_shift_1 + #shift_buff_1 * 2)
      else
         g:led(x, 8, br_shift_1)
      end

      if erase then
         g:led(x, 8, br_shift_1 + br_e_mod)
      end
   end
   
   -- shift_2
   for x = 9, 11 do
      if shift_2 then
         g:led(x, 8, br_shift_2 + #shift_buff_2 * 2)
      else
         g:led(x, 8, br_shift_2)
      end

      if erase and not shift_1 then 
         g:led(x, 8, br_e_a)
      end
   end
   
   -- patterns
   for x = 1, 4 do		
      if p.state[x] == "empty" then
         g:led(x + 12, 5, br_pat_e)
      end
      
      if p.state[x] == "full" then
         g:led(x + 12, 5, br_pat_f)
      end

      if p_current == x and p.state[x] == "empty" then
         g:led(x + 12, 5, br_pat_c)
      end	

      if p_current == x and p.state[x] == "full" then
         g:led(x + 12, 5, br_pat_c_f)
      end	
      
      if shift_2 and not shift_1 then
         if p.state[x] == "empty" then
            g:led(x + 12, 5, br_pat_e + br_pat_mod)
         end
         
         if p.state[x] == "full" then
            g:led(x + 12, 5, br_pat_f + br_pat_mod)
         end
         
         if p_current == x and p.state[x] == "empty" then
            g:led(x + 12, 5, br_pat_c + br_pat_mod)
         end	
         
         if p_current == x and p.state[x] == "full" then
            g:led(x + 12, 5, br_pat_c_f + br_pat_mod)
         end	
      end
      
      if erase then
         if p.state[x] == "full" then
            g:led(x + 12, 5, br_pat_f - br_pat_mod)
         end

         if p_current == x and p.state[x] == "empty" then
            g:led(x + 12, 5, br_pat_c - br_pat_mod)
         end	

         if p_current == x and p.state[x] == "full" then
            g:led(x + 12, 5, br_pat_c_f - br_pat_mod)
         end	
      end
   end		
   
   -- erase
   if erase then
      g:led(16, 6, br_e_a)
   elseif shift_1 then
      g:led(16, 6, br_e + br_e_mod)
   elseif shift_2 and not shift_1 then
      g:led(16, 6, br_e_a)
   else
      g:led(16, 6, br_e)
   end
   
   -- select
   if select then
      g:led(15, 6, br_sel_a)
   else
      g:led(15, 6, br_sel)
   end

   -- reset
   if seq_reset then
      g:led(14, 6, br_reset_a)
   else
      g:led(14, 6, br_reset)
   end
   
   -- play
   if seq_play then
      if shift_2 then
         if t[1].forward then
            g:led(13, 6, br_play_a + frame_anim - frames)
         end
         if not t[1].forward then
            g:led(13, 6, br_play_a - frame_anim)
         end
      end
      if not shift_2 then
         if t[1].forward then
            g:led(13, 6, br_play_a - frame_anim)
         end
         if not t[1].forward then
            g:led(13, 6, br_play_a + frame_anim - frames)
         end
      end
   end

   if not seq_play then
      g:led(13, 6, br_play)
   end
   
   -- fill
   for x = 13, 16 do
      for y = 7, 8 do
         if fill then
            g:led(x, y, br_fill_a + #fill_buff)
         else
            g:led(x, y, br_fill)
         end
      end
   end

   -- step edit
   for y = 5, 7 do
      for x = 5, 12 do
         local substep = (x - 4) + ((y - 5) * 8)
         local track = edit.track
         local step = t[track]:step_2_index(edit.step)

         if t[track].substep == substep and not seq_play then
            g:led(x, y, br_sub + br_sub_t)
         else
            g:led(x, y, br_sub)
         end

         if t[track].data[step + substep - 1] == 1 then
            if t[track].substep == substep and not seq_play then
               g:led(x, y, br_sub_a + br_sub_t)
            else
               g:led(x, y, br_sub_a)
            end
         end
      end
   end

   -- step edit: blink selection
   do
      local track = edit.track
      local step = edit.step
      local edit = t[track]

      if edit.data_step[step] == 0 then
         if select then
            if edit.step < edit.loop_start or edit.step > edit.loop_end then
               g:led(step, track, br_seq_l + br_sel_mod - frame_anim)
            else
               g:led(step, track, br_seq_l + br_sel_mod - frame_anim)
            end
         else
            if edit.step < edit.loop_start or edit.step > edit.loop_end then
               g:led(step, track, br_seq_l - math.floor(frame_anim / 3))
            else
               g:led(step, track, br_seq_l - math.floor(frame_anim / 3))
            end
         end
      end

      if edit.data_step[step] == 1 then
         g:led(step, track, br_seq_a - frame_anim)
      end
   end
   
   -- tracers
   for y = 1, 4 do
      if edit.track == y and edit.step == t[y].step then -- blink tracer on edited step
         g:led(t[y].step, y, br_seq_t - frame_anim)
      else 
         g:led(t[y].step, y, br_seq_t) -- normal bright tracer
      end
   end
      
   g:refresh()
end

function g_blink_triggers()
   for x = 1, 4 do
      if trig_pulled[x] then
         g:led(x, 7, br_t_val[x])
         g:led(x, 8, br_t_val[x])
         trig_pulled[x] = false
      end
      
      if t[x].data[t[x].index] == 1 and not mute[x] then
         g:led(x, 7, br_t_h)
         g:led(x, 8, br_t_h)
         trig_pulled[x] = true
      end 

      g:refresh()
   end
end

-- norns: interaction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function key(n, z)
   if n == 1 then
      if z == 1 then k1_held = true else k1_held = false end
   end
   
   if n == 2 then -- play
      if z == 1 then
         if seq_play then
            clock.cancel(clk_main)
            seq_play = false
            halt_step = t[edit.track].step
         else
            clk_main = clock.run(c_main)
            seq_play = true
         end
      end
   end
   
   if n == 3 then -- reset
      if z == 1 then
         for n = 1, 4 do
            t[n]:reset()
         end
      end
      halt_step = 1
   end
end

function enc(n, d)
   if n == 1 then
      params:delta("clock_tempo", d)
   end

   if n == 2 then -- randomize
      for n = 1, d do
         if d > 0 then -- add step to random 16th
            for brute_force = 1, 64 do            
               local track = math.random(4)
               local step = math.random(16)
               local index = t[track]:step_2_index(step)
               if t[track].data_step[step] == 0 then
                  t[track]:write(1, index)
               end
               break
            end       
         end 
      end

      if d < 0 then -- remove last step (either programed or random)
         for n = 1, math.abs(d) do
            if #active_steps > 0 then
               local track = t[active_steps[#active_steps].track]
               local step = track:index_2_step(active_steps[#active_steps].index)
               track:clear_step(step)
            end
         end
      end
   end

   if n == 3 then
      if d > 0 then -- add step to random substep
         for brute_force = 1, 4 * 384 do
            local track = math.random(4)
            local index = math.random(384)
            if t[track].data[index] == 0 then
               t[track]:write(1, index)
            end
            break
         end       
      end 
   
      if d < 0 then -- remove last step (either programed or random)
         if #active_steps > 0 then
            local track = t[active_steps[#active_steps].track]
            local index = active_steps[#active_steps].index
            track:write(0, index)
         end
      end
   end
end

-- norns: screen
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw()
   screen.clear()
   screen.font_face(1)
   screen.level(15)
   screen.move(8, 60)
   screen.font_size(16)
   screen.text("bpm:")
   screen.move(120, 60)
   screen.font_size(32)
   screen.text_right(params:get("clock_tempo"))
   screen.update()
end

function refresh()
   redraw()
end

-- tidy up before we go
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function cleanup()
   nb:stop_all()
   if save_on_exit then
      params:write("/home/we/dust/data/drumseq/drumseq_state.pset")
   end
end
