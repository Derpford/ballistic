class HitInfo {
    // Can hold either a line hit or an actor hit.
    // Could technically be both, though that should be impossible, probably...
    Actor hitActor;
    Line hitLine;
    Vector3 hitPos;
}

class BallisticTracer : LineTracer {
    // Handles calling Activate on all the lines we cross.
    Actor owner;
    BProj bullet;

    Array<Actor> hitActors;
    // Array<Vector3> hitActorPos; // Maybe use this for damage calc?
    Array<Line> hitLines;
    // Array<Vector3> hitLinePos;
    Array<HitInfo> hits;

    override ETraceStatus TraceCallback() {
        HitInfo h = HitInfo(new("HitInfo"));
        int result = TRACE_Stop;
        h.hitPos = results.hitPos;
        if (results.HitType == TRACE_HitWall) {
            if (hitLines.find(results.HitLine) != hitLines.size()) { return TRACE_Skip; }
            h.hitLine = results.hitLine;
            hitLines.push(results.hitLine);
            if (results.HitLine.Flags & (!(Line.ML_TWOSIDED) | Line.ML_BLOCKPROJECTILE | Line.ML_BLOCKHITSCAN | Line.ML_BLOCKEVERYTHING)) {
                if (bullet.WallPenCheck(results.HitLine)) {
                    result = TRACE_Continue;
                }
            } else {
                result = TRACE_Skip; // Continue on non-blocking walls.
            }
        }
        if (results.HitType == TRACE_HitActor) {
            if (hitActors.find(results.HitActor) != hitActors.size()) { return TRACE_Skip; }
            if (results.hitActor == owner) { return TRACE_Skip; }
            h.hitActor = results.HitActor;
            hitActors.push(results.hitActor);
            bool pen = bullet.MobPenCheck(results.HitActor);
            if (!(results.HitActor.bSOLID | results.HitActor.bSHOOTABLE) || pen) {
                result = TRACE_Skip; // Continue on actors that are nonsolid, nonshootable, or penetrated.
            }
        }

        hits.push(h);

        return result; // default to stopping.
    }
}

class BProj : Actor {
    double distance;
    // tracks the distance the bullet has traveled.
    vector3 facing;
    // Set to the current velocity on spawn. Represents the direction the bullet is facing.
    // The closer this is to vel, the better.
    double droprange, droprate;
    Property Drop: droprange,droprate;
    // droprange is the distance at which the bullet falls at droprate per second.
    double swayrange, swayrate;
    vector2 sway;
    Property Sway: swayrange, swayrate;
    // swayrange is the distance at which the bullet has a maximum sideways drift of swayrate per second.
    double aeromult;
    Property Aero: aeromult;
    // How much the bullet's current trajectory is affected by its current facing direction.
    // vel.length() * aeromult is transferred to the bullet's facing dir per second.
    double stabrange, stabrate;
    Property Stability: stabrange, stabrate;
    // stabrange is the distance at which the bullet tumbles at stabrate per second.
    double optrange;
    Property OptRange: optrange;
    // Subtracted from distance when calculating the behavior of other properties.
    double tumblefactor;
    Property TumbleFactor: tumblefactor;
    // How much the damage output can be reduced by. 0.0 means that tumbling has no effect on damage. 1.0 means that a bullet facing directly away from the target will do no damage. 2.0 means a bullet perpendicular to the target will do no damage.
    double basedmg;
    Property Damage: basedmg;
    // The amount of damage a bullet does when it lands head-on.
    int steps;
    Property Steps: steps;
    // How many movement steps per tick.
    double penrate;
    // How much velocity is lost per unit of distance spent penetrating something? In units.
    double pendeviate;
    // How far can the bullet's angle/pitch be adjusted per unit of distance spent penetrating something? In degrees.
    Property Penetration: penrate, pendeviate;

    double maxdist;
    Property MaxDistance: maxdist; // The absolute maximum travel distance of this bullet, to keep bugs from causing infinite bullet travel.

    default {
        Radius 0;
        Height 0;
        Speed 180;
        +MISSILE;

        BProj.Drop 2048,1;
        BProj.Sway 2048,1;
        BProj.Aero 0;
        BProj.Stability 2048,1;
        BProj.OptRange 1024;
        BProj.TumbleFactor 1.0;
        BProj.Damage 50;
        BProj.Steps 4;
        BProj.Penetration 0.5,0.5;
        BProj.MaxDistance 8192;
        Decal "BulletChip";
    }

    Vector3 RPVector(Vector3 v, double ang, double pit) {
        // Rotates a vector3 in two directions at once.
        vector2 xy = v.xy;
        vector2 hz = (v.z,v.xy.length());
        xy = RotateVector(xy,ang);
        hz = RotateVector(hz,pit);
        return (xy.x,xy.y,hz.x);
    }

    double GetDistance(bool floor = true) {
        if (floor) {
            return max(0,distance - optrange);
        } else {
            return distance - optrange;
        }
    }

    virtual clearscope int DamageCalc() {
        double tumble = facing.unit() dot vel.unit();
        double tumblemult = 1.0 - (max(0,1.0 - tumble) * tumblefactor);
        double dmg = basedmg * tumblemult;
        double velmult = vel.length() / speed;
        return floor(dmg * velmult);
    }

    virtual void DoStability(double rate) {
        //Adjusts our facingvector in a random direction at a random amplitude.
        double atr = (GetDistance() / stabrange) * frandom(-stabrate,stabrate) * rate;
        double ptr = (GetDistance() / stabrange) * frandom(-stabrate,stabrate) * rate;

        facing = RPVector(facing,atr,ptr);
    }

    virtual void DoDrift(double rate) {
        // Adjusts vel in a random direction.
        if (sway == (0,0)) {
            sway = (frandom(-1,1),frandom(-1,1));
        }

        double asr = (GetDistance() / swayrange) * swayrate * sway.x * rate;
        double psr = (GetDistance() / swayrange) * swayrate * sway.y * rate;

        vel = RPVector(vel,asr,psr);
    }

    virtual void DoDrop(double rate) {
        // Adjusts vel purely downward.
        double dr = (GetDistance(false) / droprange) * droprate * rate;
        vel.z -= dr;
    }

    virtual clearscope bool MobPenCheck(Actor other) {
        // First, check how big the target's radius is. 
        // We can only overpenetrate if we have enough velocity to cross the target in one tick.
        if (other.radius > vel.length()) { 
            return false;
        }
        // Next, check against the target's health. Overpen is guaranteed if damage is higher than target's health.
        double hptarget = (double(DamageCalc()) / double(other.health));
        if (frandom(0,1) < hptarget) { 
            return true; 
        }
        return false; // TODO: penetration checks
    }

    virtual clearscope bool WallPenCheck(Line l) {
        return false; // TODO
    }

    virtual bool,double StepMove(int step, double dist) {
        // Moves the projectile up to dist, returning true if the next StepMove should be called or false to stop.
        // Also returns the actual distance moved.
        double dt = 1./35.;
        double rate = dt / double(steps);
        DoStability(rate);
        DoDrift(rate);
        DoDrop(rate);

        // console.printf("Traveling %0.1f",dist);

        // fLineTraceData d;
        // double ang = VectorAngle(vel.x,vel.y);
        // double pit = 90 - VectorAngle(vel.z,vel.xy.length());
        // LineTrace(ang,dist,-pit,data:d); // Not sure why LineTrace acts like this...oh well
        BallisticTracer bt = New("BallisticTracer");
        bt.bullet = self;
        bt.owner = target;
        bool cont = !bt.trace(pos,cursector,vel.unit(),vel.length(),TRACE_HitSky);

        double spdloss;
        double hitdeviate;

        foreach (h : bt.hits) {
            SetOrigin(h.hitPos,true);
            Line l = h.hitLine;
            if (l) {
                l.Activate(target,Line.front,SPAC_Impact|SPAC_PCross);
                l.Activate(target,Line.back,SPAC_Impact|SPAC_PCross); // Just in case.
                A_SprayDecal("BulletChip",direction:vel.unit());
            }
            Actor a = h.hitActor;
            if (a) {
                a.DamageMobj(self,target,DamageCalc(),damagetype);
                spdloss += a.radius * penrate;
                hitdeviate += a.radius * pendeviate;
            }
        }

        SetOrigin(bt.results.HitPos,true);

        vel = RPVector(vel.unit(), frandom(-hitdeviate,hitdeviate), frandom(-hitdeviate,hitdeviate)) * (vel.length() - spdloss);
        console.printf("Speed loss %f, new vel %f",spdloss,vel.length());

        return cont, bt.results.distance;
    }

    static BProj Fire(Actor owner, Class<BProj> type, double ang, double pit, double velbonus = 0, double rangebonus = 0) {
        // Fires this projectile from the owner.
        // ang and pit are relative to the owner's angle and pitch, naturally
        // velbonus gets added to speed when deciding the initial velocity, so you can emulate longer or shorter barrels
        // rangebonus gets added to optrange, for the same reason

        // First, figure out the owner's projectile fire height.
        double zoffset = (owner.height * 0.5) - owner.floorclip;
        let plr = PlayerPawn(owner);
        if (plr) {
            zoffset += plr.player.mo.AttackZOffset * plr.player.crouchFactor;
        }

        // Next, spawn the BProj.
        BProj p = BProj(owner.Spawn(type,owner.pos + (0,0,zoffset)));
        if (p) {
            p.target = owner;
            p.angle = owner.angle+ang;
            p.pitch = owner.pitch+pit;
            p.Vel3DFromAngle(p.speed + velbonus,ang,pit);
            p.optrange += rangebonus;
        }
        
        return p;
        // Use of ammunition is not handled here. You should write a function in your weapons that calls this on the kind of BProj you're firing.
        // This will also give you an opportunity to adjust angle and pitch, i.e., so that your gun can be pointed in a direction other than where your camera's pointing.
    }

    override void PostBeginPlay() {
        super.PostBeginPlay();
        facing = vel.unit();
        if (target) {
            SetOrigin(pos + vel.unit() * (target.radius + 0.5),false);
            // Warp us out of our owner.
        }
    }

    override void Tick() {
        for (int i = 0; i < steps; i++) {
            bool cont; double dist;
            double tgtdist = vel.length()/double(steps);
            [cont,dist] = StepMove(i,tgtdist);
            distance += dist;
            if (!cont) { Die(null,null); break; }
        }

        if (distance > maxdist) {
            Die(null,null);
        }
    }

    states {
        Spawn:
            PUFF A -1;
    }
}

class TestGun : Weapon {
    default {
        Weapon.SlotNumber 2;
    }

    action void Shoot() {
        BProj.Fire(invoker.owner,"BProj",invoker.owner.angle,invoker.owner.pitch);
    }

    states {
        Select:
            PISG A 1 A_Raise(18);
            Loop;
        DeSelect:
            PISG A 1 A_Lower(18);
            Loop;

        Ready:
            PISG A 1 A_WeaponReady();
            Loop;

        Fire:
            PISG B 1 Shoot();
            PISG C 1;
            Goto Ready;
    }
}