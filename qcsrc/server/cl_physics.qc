.float race_penalty;
.float restart_jump;

float sv_accelerate;
float sv_friction;
float sv_maxspeed;
float sv_airaccelerate;
float sv_maxairspeed;
float sv_stopspeed;
float sv_gravity;
float sv_airaccel_sideways_friction;
float sv_airaccel_qw;
float sv_airstopaccelerate;
float sv_airstrafeaccelerate;
float sv_maxairstrafespeed;
float sv_aircontrol;
float sv_warsowbunny_airforwardaccel;
float sv_warsowbunny_accel;
float sv_warsowbunny_topspeed;
float sv_warsowbunny_turnaccel;
float sv_warsowbunny_backtosideratio;

.float ladder_time;
.entity ladder_entity;
.float gravity;
.float swamp_slowdown;
.float lastflags;
.float lastground;
.float wasFlying;
.float spectatorspeed;

#define SHTEST_DELTA 10
#define SHTEST_THRESHOLD 1.1
.float shtest_next;
.float shtest_accumulator;
.float doublejump_nextjumptime;

.float lastwj;

/*
=============
PlayerJump

When you press the jump key
=============
*/
void PlayerJump (void)
{
	float mjumpheight;

	mjumpheight = sv_jumpvelocity;
	if (self.waterlevel >= WATERLEVEL_SWIMMING)
	{
		if (self.watertype == CONTENT_WATER)
			self.velocity_z = 200;
		else if (self.watertype == CONTENT_SLIME)
			self.velocity_z = 80;
		else
			self.velocity_z = 50;

		return;
	}

	if(g_freeze)
	if(self.frozen)
		return;

	if (!(self.flags & FL_ONGROUND))
		return;

	if(!sv_pogostick)
		if (!(self.flags & FL_JUMPRELEASED))
			return;

	if(self.health <= g_bloodloss)
		return;

	if(sv_doublejump)
		if(time < self.doublejump_nextjumptime)
			return;

	if(g_runematch)
	{
		if(self.runes & RUNE_SPEED)
		{
			if(self.runes & CURSE_SLOW)
				mjumpheight = mjumpheight * cvar("g_balance_rune_speed_combo_jumpheight");
			else
				mjumpheight = mjumpheight * cvar("g_balance_rune_speed_jumpheight");
		}
		else if(self.runes & CURSE_SLOW)
		{
			mjumpheight = mjumpheight * cvar("g_balance_curse_slow_jumpheight");
		}
	}

	if(g_minstagib && (self.items & IT_INVINCIBLE))
	{
		mjumpheight = mjumpheight * cvar("g_minstagib_speed_jumpheight");
	}

	if(!(self.lastflags & FL_ONGROUND))
	{
		if(cvar("speedmeter"))
			dprint(strcat("landing velocity: ", vtos(self.velocity), " (abs: ", ftos(vlen(self.velocity)), ")\n"));
		if(self.lastground < time - 0.3)
			self.velocity = self.velocity * (1 - cvar("sv_friction_on_land"));
		if(self.jumppadcount > 1)
			dprint(strcat(ftos(self.jumppadcount), "x jumppad combo\n"));
		self.jumppadcount = 0;
	}

	self.velocity_z = self.velocity_z + mjumpheight;
	self.oldvelocity_z = self.velocity_z;
	self.lastwj = time - 0.8; // a clever little trick to prevent walljumping off sidewalks/stairs/etc. right after the initial jump

	self.flags &~= FL_ONGROUND;
	self.flags &~= FL_JUMPRELEASED;

	if (self.crouch)
		setanim(self, self.anim_duckjump, FALSE, TRUE, TRUE);
	else
		setanim(self, self.anim_jump, FALSE, TRUE, TRUE);

	if(g_jump_grunt)
		PlayerSound(playersound_jump, CHAN_PLAYER, VOICETYPE_PLAYERSOUND);

	if(sv_doublejump)
	{
		// we're moving upwards at self.velocity_z
		// only allow jumping after we got 3 units upwards
		// so we for sure leave the FL_ONGROUND check
		//
		// but as this sucks because of factoring in gravity, we'll just do it
		// for 4 units, and constant velocity
		self.doublejump_nextjumptime = time + 4 / max(40, self.velocity_z); // max 0.1s blocking of jumps
	}

	self.restart_jump = -1; // restart jump anim next time
	// value -1 is used to not use the teleport bit (workaround for tiny hitch when re-jumping)
}

void CheckWaterJump()
{
	local vector start, end;

// check for a jump-out-of-water
	makevectors (self.angles);
	start = self.origin;
	start_z = start_z + 8;
	v_forward_z = 0;
	normalize(v_forward);
	end = start + v_forward*24;
	traceline (start, end, TRUE, self);
	if (trace_fraction < 1)
	{	// solid at waist
		start_z = start_z + self.maxs_z - 8;
		end = start + v_forward*24;
		self.movedir = trace_plane_normal * -50;
		traceline (start, end, TRUE, self);
		if (trace_fraction == 1)
		{	// open at eye level
			self.flags |= FL_WATERJUMP;
			self.velocity_z = 225;
			self.flags &~= FL_JUMPRELEASED;
			self.teleport_time = time + 2;	// safety net
			return;
		}
	}
};

float racecar_angle(float forward, float down)
{
	float ret, angle_mult;

	if(forward < 0)
	{
		forward = -forward;
		down = -down;
	}

	ret = vectoyaw('0 1 0' * down + '1 0 0' * forward);

	angle_mult = forward / (800 + forward);

	if(ret > 180)
		return ret * angle_mult + 360 * (1 - angle_mult);
	else
		return ret * angle_mult;
}

void RaceCarPhysics()
{
	// using this move type for "big rigs"
	// the engine does not push the entity!

	float accel, steer, f;
	vector angles_save, rigvel;

	angles_save = self.angles;
	accel = bound(-1, self.movement_x / sv_maxspeed, 1);
	steer = bound(-1, self.movement_y / sv_maxspeed, 1);

	if(g_bugrigs_reverse_speeding)
	{
		if(accel < 0)
		{
			// back accel is DIGITAL
			// to prevent speedhack
			if(accel < -0.5)
				accel = -1;
			else
				accel = 0;
		}
	}

	self.angles_x = 0;
	self.angles_z = 0;
	makevectors(self.angles); // new forward direction!

	float myspeed, upspeed, steerfactor, accelfactor;

	if(self.flags & FL_ONGROUND || g_bugrigs_air_steering)
	{
		myspeed = self.velocity * v_forward;
		upspeed = self.velocity * v_up;

		// responsiveness factor for steering and acceleration
		f = 1 / (1 + pow(max(-myspeed, myspeed) / g_bugrigs_speed_ref, g_bugrigs_speed_pow));
		//MAXIMA: f(v) := 1 / (1 + (v / g_bugrigs_speed_ref) ^ g_bugrigs_speed_pow);

		if(myspeed < 0 && g_bugrigs_reverse_spinning)
			steerfactor = -myspeed * g_bugrigs_steer;
		else
			steerfactor = -myspeed * f * g_bugrigs_steer;

		if(myspeed < 0 && g_bugrigs_reverse_speeding)
			accelfactor = g_bugrigs_accel;
		else
			accelfactor = f * g_bugrigs_accel;
		//MAXIMA: accel(v) := f(v) * g_bugrigs_accel;

		if(accel < 0)
		{
			if(myspeed > 0)
			{
				myspeed = max(0, myspeed - frametime * (g_bugrigs_friction_floor - g_bugrigs_friction_brake * accel));
			}
			else
			{
				if(!g_bugrigs_reverse_speeding)
					myspeed = min(0, myspeed + frametime * g_bugrigs_friction_floor);
			}
		}
		else
		{
			if(myspeed >= 0)
			{
				myspeed = max(0, myspeed - frametime * g_bugrigs_friction_floor);
			}
			else
			{
				if(g_bugrigs_reverse_stopping)
					myspeed = 0;
				else
					myspeed = min(0, myspeed + frametime * (g_bugrigs_friction_floor + g_bugrigs_friction_brake * accel));
			}
		}
		// terminal velocity = velocity at which 50 == accelfactor, that is, 1549 units/sec
		//MAXIMA: friction(v) := g_bugrigs_friction_floor;

		self.angles_y += steer * frametime * steerfactor; // apply steering
		makevectors(self.angles); // new forward direction!

		myspeed += accel * accelfactor * frametime;

		rigvel = myspeed * v_forward + '0 0 1' * upspeed;
	}
	else
	{
		myspeed = vlen(self.velocity);

		// responsiveness factor for steering and acceleration
		f = 1 / (1 + pow(max(0, myspeed / g_bugrigs_speed_ref), g_bugrigs_speed_pow));
		steerfactor = -myspeed * f;
		self.angles_y += steer * frametime * steerfactor; // apply steering

		rigvel = self.velocity;
		makevectors(self.angles); // new forward direction!
	}

	rigvel = rigvel * max(0, 1 - vlen(rigvel) * g_bugrigs_friction_air * frametime);
	//MAXIMA: airfriction(v) := v * v * g_bugrigs_friction_air;
	//MAXIMA: total_acceleration(v) := accel(v) - friction(v) - airfriction(v);
	//MAXIMA: solve(total_acceleration(v) = 0, v);

	if(g_bugrigs_planar_movement)
	{
		vector rigvel_xy, neworigin, up;
		float mt;

		rigvel_z -= frametime * sv_gravity; // 4x gravity plays better
		rigvel_xy = rigvel;
		rigvel_xy_z = 0;

		if(g_bugrigs_planar_movement_car_jumping && !g_touchexplode) // touchexplode is a better way to handle collisions
			mt = MOVE_NORMAL;
		else
			mt = MOVE_NOMONSTERS;

		tracebox(self.origin, self.mins, self.maxs, self.origin + '0 0 1024', mt, self);
		up = trace_endpos - self.origin;

		// BUG RIGS: align the move to the surface instead of doing collision testing
		// can we move?
		tracebox(trace_endpos, self.mins, self.maxs, trace_endpos + rigvel_xy * frametime, mt, self);

		// align to surface
		tracebox(trace_endpos, self.mins, self.maxs, trace_endpos - up + '0 0 1' * rigvel_z * frametime, mt, self);

		if(trace_fraction < 0.5)
		{
			trace_fraction = 1;
			neworigin = self.origin;
		}
		else
			neworigin = trace_endpos;

		if(trace_fraction < 1)
		{
			// now set angles_x so that the car points parallel to the surface
			self.angles = vectoangles(
					'1 0 0' * v_forward_x * trace_plane_normal_z
					+
					'0 1 0' * v_forward_y * trace_plane_normal_z
					+
					'0 0 1' * -(v_forward_x * trace_plane_normal_x + v_forward_y * trace_plane_normal_y)
					);
			self.flags |= FL_ONGROUND;
		}
		else
		{
			// now set angles_x so that the car points forward, but is tilted in velocity direction
			self.flags &~= FL_ONGROUND;
		}

		self.velocity = (neworigin - self.origin) * (1.0 / frametime);
		self.movetype = MOVETYPE_NOCLIP;
	}
	else
	{
		rigvel_z -= frametime * sv_gravity; // 4x gravity plays better
		self.velocity = rigvel;
		self.movetype = MOVETYPE_FLY;
	}

	trace_fraction = 1;
	tracebox(self.origin, self.mins, self.maxs, self.origin - '0 0 4', MOVE_NORMAL, self);
	if(trace_fraction != 1)
	{
		self.angles = vectoangles2(
				'1 0 0' * v_forward_x * trace_plane_normal_z
				+
				'0 1 0' * v_forward_y * trace_plane_normal_z
				+
				'0 0 1' * -(v_forward_x * trace_plane_normal_x + v_forward_y * trace_plane_normal_y),
				trace_plane_normal
				);
	}
	else
	{
		vector vel_local;

		vel_local_x = v_forward * self.velocity;
		vel_local_y = v_right * self.velocity;
		vel_local_z = v_up * self.velocity;

		self.angles_x = racecar_angle(vel_local_x, vel_local_z);
		self.angles_z = racecar_angle(-vel_local_y, vel_local_z);
	}

	// smooth the angles
	vector vf1, vu1, smoothangles;
	makevectors(self.angles);
	f = bound(0, frametime * g_bugrigs_angle_smoothing, 1);
	if(f == 0)
		f = 1;
	vf1 = v_forward * f;
	vu1 = v_up * f;
	makevectors(angles_save);
	vf1 = vf1 + v_forward * (1 - f);
	vu1 = vu1 + v_up * (1 - f);
	smoothangles = vectoangles2(vf1, vu1);
	self.angles_x = -smoothangles_x;
	self.angles_z =  smoothangles_z;
}

void CPM_PM_Aircontrol(vector wishdir, float wishspeed)
{
	float zspeed, xyspeed, dot, k;

	if(self.movement_x == 0 || self.movement_y != 0)
		return; // can't control movement if not moving forward or backward

	zspeed = self.velocity_z;
	self.velocity_z = 0;
	xyspeed = vlen(self.velocity);
	self.velocity = normalize(self.velocity);

	dot = self.velocity * wishdir;
	k = 32;
	k *= sv_aircontrol*dot*dot*frametime;

	if(dot > 0) // we can't change direction while slowing down
		self.velocity = normalize(self.velocity * xyspeed + wishdir * k);

	self.velocity = self.velocity * xyspeed;
	self.velocity_z = zspeed;
}

void PM_Accelerate(vector wishdir, float wishspeed, float wishspeed0, float accel, float accelqw, float sidefric)
{
	float vel_straight;
	float vel_z;
	vector vel_perpend;
	float addspeed;
	float savespeed;
    
	if(sv_gameplayfix_q2airaccelerate)
		wishspeed0 = wishspeed;

	savespeed = self.velocity * self.velocity;

	vel_straight = self.velocity * wishdir;
	vel_z = self.velocity_z;
	vel_perpend = self.velocity - vel_straight * wishdir - vel_z * '0 0 1';

	addspeed = wishspeed - vel_straight;
	if(addspeed > 0)
		vel_straight = vel_straight + min(addspeed, accel * frametime * wishspeed0) * accelqw;
	if(wishspeed > 0)
		vel_straight = vel_straight + min(wishspeed, accel * frametime * wishspeed0) * (1 - accelqw);

	if(sidefric < 0 && (vel_perpend*vel_perpend))
	{
		float f, fmin;
		f = (1 + frametime * wishspeed * sidefric);
		fmin = (savespeed - vel_straight*vel_straight) / (vel_perpend*vel_perpend);
		if(fmin <= 0)
			vel_perpend = vel_perpend * f;
		else
			vel_perpend = vel_perpend * min(1, max(fmin, f));
	}
	else
		vel_perpend = vel_perpend * (1 - frametime * wishspeed * sidefric);

	self.velocity = vel_straight * wishdir + vel_z * '0 0 1' + vel_perpend;
}

void PM_AirAccelerate(vector wishdir, float wishspeed)
{
	vector curvel, wishvel, acceldir, curdir;
	float addspeed, accelspeed, curspeed, f;
	float dot;

	if(wishspeed == 0)
		return;

	curvel = self.velocity;
	curvel_z = 0;
	curspeed = vlen(curvel);

	if(wishspeed > curspeed * 1.01)
	{
		wishspeed = min(wishspeed, curspeed + sv_warsowbunny_airforwardaccel * sv_maxspeed * frametime);
	}
	else
	{
		f = max(0, (sv_warsowbunny_topspeed - curspeed) / (sv_warsowbunny_topspeed - sv_maxspeed));
		wishspeed = max(curspeed, sv_maxspeed) + sv_warsowbunny_accel * f * sv_maxspeed * frametime;
	}
	wishvel = wishdir * wishspeed;
	acceldir = wishvel - curvel;
	addspeed = vlen(acceldir);
	acceldir = normalize(acceldir);

	accelspeed = min(addspeed, sv_warsowbunny_turnaccel * sv_maxspeed * frametime);

	if(sv_warsowbunny_backtosideratio < 1)
	{
		curdir = normalize(curvel);
		dot = acceldir * curdir;
		if(dot < 0)
			acceldir = acceldir - (1 - sv_warsowbunny_backtosideratio) * dot * curdir;
	}

	self.velocity += accelspeed * acceldir;
}

.vector movement_old;
.float buttons_old;
.vector v_angle_old;
.string lastclassname;

void Nixnex_GiveCurrentWeapon();
.float() PlayerPhysplug;

string specialcommand = "xwxwxsxsxaxdxaxdx1x ";
.float specialcommand_pos;
void SpecialCommand()
{
#ifdef TETRIS
	TetrisImpulse();
#else
	if(sv_cheats || self.maycheat)
		self.impulse = 99;
	else
		print("A hollow voice says \"Plugh\".\n");
#endif
}

vector PlayerTouchWall(float dist)
{
    float max_normal, i;
    max_normal = 0.2;
    
    vector old_forward = v_forward, old_right = v_right, old_up = v_up, normal = '0 0 0';
    makevectors(self.angles);
    
    for(i = 1; i > -2; i -= 2) {
        tracebox(self.origin, self.mins + cvar("sv_stepheight") * '0 0 1' * (cvar("g_walljump_stepheightcompensate")? 1 : 0), self.maxs, self.origin + v_forward * dist * i * 2, TRUE, self);
        if(trace_fraction < 1)
        if(trace_plane_normal_z < max_normal)
        if not(trace_dphitq3surfaceflags & Q3SURFACEFLAG_NOIMPACT)
        if(vlen(self.origin - trace_endpos) < dist) {
            normal = trace_plane_normal;
            break;
        }
    }
    
    v_forward = old_forward;
    v_right = old_right;
    v_up = old_up;
    return normal;
}

void SV_PlayerPhysics()
{
	local vector wishvel, wishdir, v;
	local float wishspeed, f, maxspd_mod, spd, maxairspd, airaccel, swampspd_mod, shtest_score, buttons;
	string temps;
	float buttons_prev;
	float not_allowed_to_move;
    float isplayer;
	//string c;
    
    isplayer = self.classname == "player";
    
    // XXX: why is this in Physics? Move to PlayerPreThink/PostThink later
	if(self.movement != '0 0 0')
	{
		self.parm_idlesince = time;
		if(self.is_away)
			UnmarkAway(self);
	}
	else if(!self.is_away)
	{
		local float a = sv_autoaway;

		if(a)
		if(time - self.parm_idlesince >= a * 60)
			MarkAway(self, 0);
	}

	if(g_race || g_cts)
	{
		// if record times matter
		// ensure nothing EVIL is being done (i.e. strafebot)
		// this hinders joystick users though
		// but it still gives SOME analog control
		// TODO implement this for engine cl_movement code too (basically, clipping to the four axes)
		wishvel_x = fabs(self.movement_x);
		wishvel_y = fabs(self.movement_y);
		if(wishvel_x != 0 && wishvel_y != 0 && wishvel_x != wishvel_y)
		{
			wishvel_z = 0;
			wishspeed = vlen(wishvel);
			if(wishvel_x >= 2 * wishvel_y)
			{
				// pure X motion
				if(self.movement_x > 0)
					self.movement_x = wishspeed;
				else
					self.movement_x = -wishspeed;
				self.movement_y = 0;
			}
			else if(wishvel_y >= 2 * wishvel_x)
			{
				// pure Y motion
				self.movement_x = 0;
				if(self.movement_y > 0)
					self.movement_y = wishspeed;
				else
					self.movement_y = -wishspeed;
			}
			else
			{
				// diagonal
				if(self.movement_x > 0)
					self.movement_x = 0.70710678118654752440 * wishspeed;
				else
					self.movement_x = -0.70710678118654752440 * wishspeed;
				if(self.movement_y > 0)
					self.movement_y = 0.70710678118654752440 * wishspeed;
				else
					self.movement_y = -0.70710678118654752440 * wishspeed;
			}
		}
	}
    
    // as far as I know, fteqcc/rmqcc still does not optimize boolean expressions by default
	if (g_walljump)
	if (!(g_freeze && self.frozen) && self.health > 0)
    if (isplayer)
    if (!(self.flags & FL_ONGROUND))
    if (self.BUTTON_JUMP)
    if ((time - self.lastwj) > g_walljump_delay)
	if (!self.hook.state)
    if (!gameover)
    if (!self.hg_shield || cvar("g_walljump_shielded"))
    if (!(g_race || g_cts) || cvar("g_walljump_allowed_in_race"))
	{
		vector plane_normal;
		plane_normal = PlayerTouchWall(cvar("g_walljump_distance"));
		if (plane_normal != '0 0 0')
		{
			self.lastwj = time;
            vector kickdir, sidev = self.velocity;
            sidev_z = 0;
			float wj_force = max(cvar("g_walljump_force"), vlen(sidev) * cvar("g_walljump_force_velocityscale"));
			float wj_z_factor = cvar("g_walljump_velocity_z_factor");
            
            if(cvar("g_walljump_reflect")) {
                kickdir = normalize(sidev - 2 * (sidev * plane_normal) * plane_normal);
                if(kickdir == '0 0 0')
                    kickdir = plane_normal;
            } else
                kickdir = plane_normal;
            
            if(cvar("g_walljump_hardkick")) {
                self.velocity_x = kickdir_x * wj_force;
                self.velocity_y = kickdir_y * wj_force;
            } else {
                float wj_xy_factor = cvar("g_walljump_velocity_xy_factor");
                float cap = cvar("g_walljump_velocity_xy_cap");
                if(cap)
                    cap = max(vlen(sidev) / wj_xy_factor, wj_force);
                
                if(cvar("g_walljump_velocity_xy_factor_initial_only")) {
                    self.velocity_x = (self.velocity_x / wj_xy_factor) + (kickdir_x * wj_force);
                    self.velocity_y = (self.velocity_y / wj_xy_factor) + (kickdir_y * wj_force);
                } else {
                    self.velocity_x = (self.velocity_x + kickdir_x * wj_force) / wj_xy_factor;
                    self.velocity_y = (self.velocity_y + kickdir_y * wj_force) / wj_xy_factor;
                }
                
                if(cap) {
                    self.velocity_z = 0;
                    if(vlen(self.velocity) > cap)
                        self.velocity = normalize(self.velocity) * cap;
                }
            }
            
			self.velocity_z = sv_jumpvelocity * wj_z_factor;
			if (self.crouch) self.velocity_z *= -1; // thanks Synap for the idea
			self.oldvelocity = self.velocity;
			pointparticles(particleeffectnum("smoke_ring"), trace_endpos, plane_normal, 10);
			PlayerSound (playersound_jump, CHAN_PLAYER, VOICETYPE_PLAYERSOUND);
		}
	}

	self.race_movetime_frac += frametime;
	f = floor(self.race_movetime_frac);
	self.race_movetime_frac -= f;
	self.race_movetime_count += f;
	self.race_movetime = self.race_movetime_frac + self.race_movetime_count;

	buttons = self.BUTTON_ATCK + 2 * self.BUTTON_JUMP + 4 * self.BUTTON_ATCK2 + 8 * self.BUTTON_ZOOM + 16 * self.BUTTON_CROUCH + 32 * self.BUTTON_HOOK + 64 * self.BUTTON_USE + 128 * (self.movement_x < 0) + 256 * (self.movement_x > 0) + 512 * (self.movement_y < 0) + 1024 * (self.movement_y > 0);
	
#if 0
	if(!buttons)
		c = "x";
	else if(buttons == 1)
		c = "1";
	else if(buttons == 2)
		c = " ";
	else if(buttons == 128)
		c = "s";
	else if(buttons == 256)
		c = "w";
	else if(buttons == 512)
		c = "a";
	else if(buttons == 1024)
		c = "d";
	else
		c = "?";

	if(c == substring(specialcommand, self.specialcommand_pos, 1))
	{
		self.specialcommand_pos += 1;
		if(self.specialcommand_pos >= strlen(specialcommand))
		{
			self.specialcommand_pos = 0;
			SpecialCommand();
			return;
		}
	}
	else if(self.specialcommand_pos && (c != substring(specialcommand, self.specialcommand_pos - 1, 1)))
		self.specialcommand_pos = 0;
#endif

    if(self.PlayerPhysplug)
        if(self.PlayerPhysplug())
            return;

	if(!sv_maxidle_spectatorsareidle || self.movetype == MOVETYPE_WALK)
	{
		if(buttons != self.buttons_old || self.movement != self.movement_old || self.v_angle != self.v_angle_old)
			self.parm_idlesince = time;
	}
	buttons_prev = self.buttons_old;
	self.buttons_old = buttons;
	self.movement_old = self.movement;
	self.v_angle_old = self.v_angle;

	if(time < self.nickspamtime)
	if(self.nickspamcount >= cvar("g_nick_flood_penalty_yellow"))
	{
		// slight annoyance for nick change scripts
		self.movement = -1 * self.movement;
		self.BUTTON_ATCK = self.BUTTON_JUMP = self.BUTTON_ATCK2 = self.BUTTON_ZOOM = self.BUTTON_CROUCH = self.BUTTON_HOOK = self.BUTTON_USE = 0;

		if(self.nickspamcount >= cvar("g_nick_flood_penalty_red")) // if you are persistent and the slight annoyance above does not stop you, I'll show you!
		{
			self.angles_x = random() * 360;
			self.angles_y = random() * 360;
			// at least I'm not forcing retardedview by also assigning to angles_z
			self.fixangle = 1;
		}
	}

	if(time > self.shtest_next)
	{
		if(self.shtest_next > 0)
		{
			// self.shtest_accumulator:
			//   started at time - SHTEST_DELTA
			//   should be at SHTEST_DELTA
			shtest_score = self.shtest_accumulator / (SHTEST_DELTA + time - self.shtest_next);
			if(shtest_score > SHTEST_THRESHOLD)
				print("TIME PARADOX: shtest for ", self.netname, " said ", ftos(shtest_score), "\n");
			else if(cvar("developer_shtest"))
				dprint("okay: shtest for ", self.netname, " said ", ftos(shtest_score), "\n");
		}
		self.shtest_next = time + SHTEST_DELTA;
		self.shtest_accumulator = 0;
	}
	self.shtest_accumulator += frametime;

	if (clienttype(self) == CLIENTTYPE_BOT)
		bot_think();

	self.items &~= IT_USING_JETPACK;

	if(isplayer)
	{
		if(self.race_penalty)
			if(time > self.race_penalty)
				self.race_penalty = 0;

		not_allowed_to_move = 0;
		if(self.race_penalty)
			not_allowed_to_move = 1;
		if(!sv_ready_restart_after_countdown)
		if(time < game_starttime && !g_inf)
			not_allowed_to_move = 1;

		if(not_allowed_to_move)
		{
			self.velocity = '0 0 0';
			self.movetype = MOVETYPE_NONE;
			self.disableclientprediction = 2;
		}
		else if(self.disableclientprediction == 2)
		{
			if(self.movetype == MOVETYPE_NONE)
				self.movetype = MOVETYPE_WALK;
			self.disableclientprediction = 0;
		}
	}

	if (self.movetype == MOVETYPE_NONE)
		return;

	if (self.punchangle != '0 0 0')
	{
		f = vlen(self.punchangle) - 10 * frametime;
		if (f > 0)
			self.punchangle = normalize(self.punchangle) * f;
		else
			self.punchangle = '0 0 0';
	}

	if (self.punchvector != '0 0 0')
	{
		f = vlen(self.punchvector) - 30 * frametime;
		if (f > 0)
			self.punchvector = normalize(self.punchvector) * f;
		else
			self.punchvector = '0 0 0';
	}

	maxspd_mod = 1;

	if(g_runematch)
	{
		if(self.runes & RUNE_SPEED)
		{
			if(self.runes & CURSE_SLOW)
				maxspd_mod = maxspd_mod * cvar("g_balance_rune_speed_combo_moverate");
			else
				maxspd_mod = maxspd_mod * cvar("g_balance_rune_speed_moverate");
		}
		else if(self.runes & CURSE_SLOW)
		{
			maxspd_mod = maxspd_mod * cvar("g_balance_curse_slow_moverate");
		}
	}

	if(g_minstagib && (self.items & IT_INVINCIBLE))
	{
		maxspd_mod = cvar("g_minstagib_speed_moverate");
	}

	if(g_nexball && self.ballcarried)
	{
		maxspd_mod = cvar("g_nexball_basketball_carrier_speed");
	}
    
    if(BUFFS_PRESENT(self, BUFF_HASTE))
        maxspd_mod *= cvar("g_buffs_haste_move_rate");
    
    if(g_dodging)
        dodging_PlayerPhysics();
    Freeze_Hook_PlayerPhysics();

	swampspd_mod = 1;
	if(self.in_swamp) {
		swampspd_mod = self.swamp_slowdown; //cvar("g_balance_swamp_moverate");
	}

	if(!isplayer)
	{
		maxspd_mod = cvar("sv_spectator_speed_multiplier");
		if(!self.spectatorspeed)
			self.spectatorspeed = maxspd_mod;
		if(self.impulse && self.impulse <= 19)
		{
			if(self.lastclassname != "player")
			{
				if(self.impulse == 10 || self.impulse == 15 || self.impulse == 18)
					self.spectatorspeed = bound(1, self.spectatorspeed + 0.5, 5);
				else if(self.impulse == 11)
					self.spectatorspeed = maxspd_mod;
				else if(self.impulse == 12 || self.impulse == 16  || self.impulse == 19)
					self.spectatorspeed = bound(1, self.spectatorspeed - 0.5, 5);
				else if(self.impulse >= 1 && self.impulse <= 9)
					self.spectatorspeed = 1 + 0.5 * (self.impulse - 1);
			} // otherwise just clear
			self.impulse = 0;
		}
		maxspd_mod = self.spectatorspeed;
	}

	spd = max(sv_maxspeed, sv_maxairspeed) * maxspd_mod * swampspd_mod;
	if(self.speed != spd)
	{
		self.speed = spd;
		temps = ftos(spd);
		stuffcmd(self, strcat("cl_forwardspeed ", temps, "\n"));
		stuffcmd(self, strcat("cl_backspeed ", temps, "\n"));
		stuffcmd(self, strcat("cl_sidespeed ", temps, "\n"));
		stuffcmd(self, strcat("cl_upspeed ", temps, "\n"));
	}

	maxspd_mod *= swampspd_mod; // only one common speed modder please!
	swampspd_mod = 1;

	// if dead, behave differently
	if (self.deadflag)
		goto end;

	if (!self.fixangle && !g_bugrigs)
	{
		self.angles_x = 0;
		self.angles_y = self.v_angle_y;
		self.angles_z = 0;
	}

	if(self.flags & FL_ONGROUND)
	if(self.wasFlying)
	{
		self.wasFlying = 0;

		if(self.waterlevel < WATERLEVEL_SWIMMING)
		if(time >= self.ladder_time)
		if not(self.hook)
		{
			self.nextstep = time + 0.3 + random() * 0.1;
			trace_dphitq3surfaceflags = 0;
			tracebox(self.origin, self.mins, self.maxs, self.origin - '0 0 1', MOVE_NOMONSTERS, self);
			if not(trace_dphitq3surfaceflags & Q3SURFACEFLAG_NOSTEPS)
			{
				if(trace_dphitq3surfaceflags & Q3SURFACEFLAG_METALSTEPS)
					GlobalSound(globalsound_metalfall, CHAN_PLAYER, VOICETYPE_PLAYERSOUND);
				else
					GlobalSound(globalsound_fall, CHAN_PLAYER, VOICETYPE_PLAYERSOUND);
			}
		}
	}

	if(IsFlying(self))
		self.wasFlying = 1;

	if(isplayer)
	{
		if(sv_doublejump)
		{
			self.flags &~= FL_ONGROUND;
			tracebox(self.origin + '0 0 1', self.mins, self.maxs, self.origin - '0 0 1', MOVE_NORMAL, self);
			if(trace_fraction < 1 && trace_plane_normal_z > 0.7)
				self.flags |= FL_ONGROUND;
		}

		if (self.BUTTON_JUMP)
			PlayerJump ();
		else
			self.flags |= FL_JUMPRELEASED;

		if (self.waterlevel == WATERLEVEL_SWIMMING)
			CheckWaterJump ();
	}

	if (self.flags & FL_WATERJUMP)
	{
		self.velocity_x = self.movedir_x;
		self.velocity_y = self.movedir_y;
		if (time > self.teleport_time || self.waterlevel == WATERLEVEL_NONE)
		{
			self.flags &~= FL_WATERJUMP;
			self.teleport_time = 0;
		}
	}
	else if (g_bugrigs && isplayer)
	{
		RaceCarPhysics();
	}
	else if (self.movetype == MOVETYPE_NOCLIP || self.movetype == MOVETYPE_FLY)
	{
		// noclipping or flying
		self.flags &~= FL_ONGROUND;

		self.velocity = self.velocity * (1 - frametime * sv_friction);
		makevectors(self.v_angle);
		//wishvel = v_forward * self.movement_x + v_right * self.movement_y + v_up * self.movement_z;
		wishvel = v_forward * self.movement_x + v_right * self.movement_y + '0 0 1' * self.movement_z;
		// acceleration
		wishdir = normalize(wishvel);
		wishspeed = vlen(wishvel);
		if (wishspeed > sv_maxspeed*maxspd_mod)
			wishspeed = sv_maxspeed*maxspd_mod;
		if (time >= self.teleport_time)
			PM_Accelerate(wishdir, wishspeed, wishspeed, sv_accelerate*maxspd_mod, 1, 0);
	}
	else if (self.waterlevel >= WATERLEVEL_SWIMMING)
	{
		// swimming
		self.flags &~= FL_ONGROUND;

		makevectors(self.v_angle);
		//wishvel = v_forward * self.movement_x + v_right * self.movement_y + v_up * self.movement_z;
		wishvel = v_forward * self.movement_x + v_right * self.movement_y + '0 0 1' * self.movement_z;
		if (wishvel == '0 0 0')
			wishvel = '0 0 -60'; // drift towards bottom

		wishdir = normalize(wishvel);
		wishspeed = vlen(wishvel);
		if (wishspeed > sv_maxspeed*maxspd_mod)
			wishspeed = sv_maxspeed*maxspd_mod;
		wishspeed = wishspeed * 0.7;

		// water friction
		self.velocity = self.velocity * (1 - frametime * sv_friction);

		// water acceleration
		PM_Accelerate(wishdir, wishspeed, wishspeed, sv_accelerate*maxspd_mod, 1, 0);
	}
	else if (time < self.ladder_time)
	{
		// on a spawnfunc_func_ladder or swimming in spawnfunc_func_water
		self.flags &~= FL_ONGROUND;

		self.velocity = self.velocity * (1 - frametime * sv_friction);
		makevectors(self.v_angle);
		//wishvel = v_forward * self.movement_x + v_right * self.movement_y + v_up * self.movement_z;
		wishvel = v_forward * self.movement_x + v_right * self.movement_y + '0 0 1' * self.movement_z;
		if (self.gravity)
			self.velocity_z = self.velocity_z + self.gravity * sv_gravity * frametime;
		else
			self.velocity_z = self.velocity_z + sv_gravity * frametime;
		if (self.ladder_entity.classname == "func_water")
		{
			f = vlen(wishvel);
			if (f > self.ladder_entity.speed)
				wishvel = wishvel * (self.ladder_entity.speed / f);

			self.watertype = self.ladder_entity.skin;
			f = self.ladder_entity.origin_z + self.ladder_entity.maxs_z;
			if ((self.origin_z + self.view_ofs_z) < f)
				self.waterlevel = WATERLEVEL_SUBMERGED;
			else if ((self.origin_z + (self.mins_z + self.maxs_z) * 0.5) < f)
				self.waterlevel = WATERLEVEL_SWIMMING;
			else if ((self.origin_z + self.mins_z + 1) < f)
				self.waterlevel = WATERLEVEL_WETFEET;
			else
			{
				self.waterlevel = WATERLEVEL_NONE;
				self.watertype = CONTENT_EMPTY;
			}
		}
		// acceleration
		wishdir = normalize(wishvel);
		wishspeed = vlen(wishvel);
		if (wishspeed > sv_maxspeed*maxspd_mod)
			wishspeed = sv_maxspeed*maxspd_mod;
		if (time >= self.teleport_time)
		{
			// water acceleration
			PM_Accelerate(wishdir, wishspeed, wishspeed, sv_accelerate*maxspd_mod, 1, 0);
		}
	}
	else if((self.items & IT_JETPACK) && self.BUTTON_HOOK && (!cvar("g_jetpack_fuel") || self.ammo_fuel >= 0.01 || self.items & IT_UNLIMITED_WEAPON_AMMO) && (!g_freeze || !self.frozen))
	{
		//makevectors(self.v_angle_y * '0 1 0');
		makevectors(self.v_angle);
		wishvel = v_forward * self.movement_x + v_right * self.movement_y;
		// add remaining speed as Z component
		maxairspd = sv_maxairspeed*max(1, maxspd_mod);
		// fix speedhacks :P
		wishvel = normalize(wishvel) * min(vlen(wishvel) / maxairspd, 1);
		// add the unused velocity as up component
		wishvel_z = 0;

		// if(self.BUTTON_JUMP)
			wishvel_z = sqrt(max(0, 1 - wishvel * wishvel));

		// it is now normalized, so...
		float a_side, a_up, a_add, a_diff;
		a_side = cvar("g_jetpack_acceleration_side");
		a_up = cvar("g_jetpack_acceleration_up");
		a_add = cvar("g_jetpack_antigravity") * sv_gravity;

		wishvel_x *= a_side;
		wishvel_y *= a_side;
		wishvel_z *= a_up;
		wishvel_z += a_add;

		float best;
		best = 0;
		//////////////////////////////////////////////////////////////////////////////////////
		// finding the maximum over all vectors of above form
		// with wishvel having an absolute value of 1
		//////////////////////////////////////////////////////////////////////////////////////
		// we're finding the maximum over
		//   f(a_side, a_up, a_add, z) := a_side * (1 - z^2) + (a_add + a_up * z)^2;
		// for z in the range from -1 to 1
		//////////////////////////////////////////////////////////////////////////////////////
		// maximum is EITHER attained at the single extreme point:
		a_diff = a_side * a_side - a_up * a_up;
		if(a_diff != 0)
		{
			f = a_add * a_up / a_diff; // this is the zero of diff(f(a_side, a_up, a_add, z), z)
			if(f > -1 && f < 1) // can it be attained?
			{
				best = (a_diff + a_add * a_add) * (a_diff + a_up * a_up) / a_diff;
				//print("middle\n");
			}
		}
		// OR attained at z = 1:
		f = (a_up + a_add) * (a_up + a_add);
		if(f > best)
		{
			best = f;
			//print("top\n");
		}
		// OR attained at z = -1:
		f = (a_up - a_add) * (a_up - a_add);
		if(f > best)
		{
			best = f;
			//print("bottom\n");
		}
		best = sqrt(best);
		//////////////////////////////////////////////////////////////////////////////////////

		//print("best possible acceleration: ", ftos(best), "\n");

		float fxy, fz;
		fxy = bound(0, 1 - (self.velocity * normalize(wishvel_x * '1 0 0' + wishvel_y * '0 1 0')) / cvar("g_jetpack_maxspeed_side"), 1);
		if(wishvel_z - sv_gravity > 0)
			fz = bound(0, 1 - self.velocity_z / cvar("g_jetpack_maxspeed_up"), 1);
		else
			fz = bound(0, 1 + self.velocity_z / cvar("g_jetpack_maxspeed_up"), 1);

		float fvel;
		fvel = vlen(wishvel);
		wishvel_x *= fxy;
		wishvel_y *= fxy;
		wishvel_z = (wishvel_z - sv_gravity) * fz + sv_gravity;

		fvel = min(1, vlen(wishvel) / best);
		if(cvar("g_jetpack_fuel") && !(self.items & IT_UNLIMITED_WEAPON_AMMO))
			f = min(1, self.ammo_fuel / (cvar("g_jetpack_fuel") * frametime * fvel));
		else
			f = 1;

		//print("this acceleration: ", ftos(vlen(wishvel) * f), "\n");

		if (f > 0 && wishvel != '0 0 0')
		{
			self.velocity = self.velocity + wishvel * f * frametime;
			if not(self.items & IT_UNLIMITED_WEAPON_AMMO)
				self.ammo_fuel -= cvar("g_jetpack_fuel") * frametime * fvel * f;
			self.flags &~= FL_ONGROUND;
			self.items |= IT_USING_JETPACK;

			// jetpack also inhibits health regeneration, but only for 1 second
			self.pauseregen_finished = max(self.pauseregen_finished, time + cvar("g_balance_pause_fuel_regen"));
		}
	}
	else if (self.flags & FL_ONGROUND)
	{
		// we get here if we ran out of ammo
		if((self.items & IT_JETPACK) && self.BUTTON_HOOK && !(buttons_prev & 32) && (!g_freeze || !self.frozen))
			sprint(self, "You don't have any fuel for the ^2Jetpack\n");

		// walking
		makevectors(self.v_angle_y * '0 1 0');
		wishvel = v_forward * self.movement_x + v_right * self.movement_y;

		if(!(self.lastflags & FL_ONGROUND))
		{
			if(cvar("speedmeter"))
				dprint(strcat("landing velocity: ", vtos(self.velocity), " (abs: ", ftos(vlen(self.velocity)), ")\n"));
			if(self.lastground < time - 0.3)
				self.velocity = self.velocity * (1 - cvar("sv_friction_on_land"));
			if(self.jumppadcount > 1)
				dprint(strcat(ftos(self.jumppadcount), "x jumppad combo\n"));
			self.jumppadcount = 0;
		}

#ifdef LETS_TEST_FTEQCC
		if(self.velocity_x || self.velocity_y)
		{
			// good
		}
		else
		{
			if(self.velocity_x)
				checkclient();
			if(self.velocity_y)
				checkclient();
		}
#endif

		v = self.velocity;
		v_z = 0;
		f = vlen(v);
		if(f > 0)
		{
			if (f < sv_stopspeed)
				f = 1 - frametime * (sv_stopspeed / f) * sv_friction;
			else
				f = 1 - frametime * sv_friction;
			if (f > 0)
				self.velocity = self.velocity * f;
			else
				self.velocity = '0 0 0';
		}

		// acceleration
		wishdir = normalize(wishvel);
		wishspeed = vlen(wishvel);
		if (wishspeed > sv_maxspeed*maxspd_mod)
			wishspeed = sv_maxspeed*maxspd_mod;
		if (self.crouch)
			wishspeed = wishspeed * 0.5;
		if (time >= self.teleport_time)
			PM_Accelerate(wishdir, wishspeed, wishspeed, sv_accelerate*maxspd_mod, 1, 0);
	}
	else
	{
		float wishspeed0;
		// we get here if we ran out of ammo
		if((self.items & IT_JETPACK) && self.BUTTON_HOOK && !(buttons_prev & 32))
			sprint(self, "You don't have any fuel for the ^2Jetpack\n");

		if(maxspd_mod < 1)
		{
			maxairspd = sv_maxairspeed*maxspd_mod;
			airaccel = sv_airaccelerate*maxspd_mod;
		}
		else
		{
			maxairspd = sv_maxairspeed;
			airaccel = sv_airaccelerate;
		}
		// airborn
		makevectors(self.v_angle_y * '0 1 0');
		wishvel = v_forward * self.movement_x + v_right * self.movement_y;
		// acceleration
		wishdir = normalize(wishvel);
		wishspeed = wishspeed0 = vlen(wishvel);
		if (wishspeed0 > sv_maxspeed*maxspd_mod)
			wishspeed0 = sv_maxspeed*maxspd_mod;
		if (wishspeed > maxairspd)
			wishspeed = maxairspd;
		if (self.crouch)
			wishspeed = wishspeed * 0.5;
		if (time >= self.teleport_time)
		{
			float accelerating;
			float wishspeed2;
			float airaccelqw;

			airaccelqw = sv_airaccel_qw;
			accelerating = (self.velocity * wishdir > 0);
			wishspeed2 = wishspeed;

			// CPM
			if(sv_airstopaccelerate)
				if(self.velocity * wishdir < 0)
					airaccel = sv_airstopaccelerate*maxspd_mod;
			if(self.movement_x == 0 && self.movement_y != 0)
			{
				if(sv_maxairstrafespeed)
				{
					wishspeed = min(wishspeed, sv_maxairstrafespeed*maxspd_mod);
					if(sv_maxairstrafespeed < sv_maxairspeed)
						airaccelqw = 1;
				}
				if(sv_airstrafeaccelerate)
				{
					airaccel = sv_airstrafeaccelerate*maxspd_mod;
					if(sv_airstrafeaccelerate > sv_airaccelerate)
						airaccelqw = 1;
				}
			}
			// !CPM

			if(sv_warsowbunny_turnaccel && accelerating && self.movement_y == 0 && self.movement_x != 0)
				PM_AirAccelerate(wishdir, wishspeed);
			else
				PM_Accelerate(wishdir, wishspeed, wishspeed0, airaccel, airaccelqw, sv_airaccel_sideways_friction / maxairspd);

			if(sv_aircontrol)
				CPM_PM_Aircontrol(wishdir, wishspeed2);
		}
	}

:end
	if(self.flags & FL_ONGROUND)
		self.lastground = time;

	self.lastflags = self.flags;
	self.lastclassname = self.classname;
};
