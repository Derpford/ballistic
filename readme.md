# Ballistic Lib

Hey, you know that thing Hideous Destructor does, with the fake-projectile hitscan shots?

I figure, what if I made that a relatively simple library that can be dropped into other stuff more easily? This is also partly because I wanna make my own stuff in the same vein, and while I usually use FastProjectiles and funny Tick() shenanigans for this, I think it'd be fun to architect something like what HD does.

# Anatomy of a Ballistic Lib Weapon

## BallisticProj
A `BProj` is, as you might have guessed, a projectile based on Ballistic Lib's code. It has several key properties and functions that govern how it works:

### Drop: double, double
How much the bullet drops, described by two numbers: peak range, and peak drop rate per second.

The amount the bullet drops by, by default, is `(distance / peakrange) * droprate`. In other words, you can think of this property as "At `range`, the bullet drops `units` per second".

Bullet drop should always be in the direction of gravity for obvious reasons.

Bullet drop can be changed by overriding the `DoDrop()` function.

### Sway: double, double
How much the bullet 'sways' horizontally and vertically, described by two numbers: peak range, and peak sway rate per second.

Like with Drop, sway is calculated as `(distance / peakrange) * swayrate`. However, sway is partially randomized--at firing, the bullet is given a 'spin' direction, described as a vector2 (horizontal, vertical). The sway rate is then applied to this vector2, which is then added to the bullet's horizontal velocity (perpendicular to current vel) and vertical velocity. In short: At `range`, the bullet deviates from its flight path by `units` per second in a random direction chosen when the bullet is fired. As you might expect, this combines with Drop to make bullets tend to fly more horizontally than vertically.

Bullet sway can be changed by overriding the `DoDrift()` function.

### Aero: double
How much the bullet's velocity is affected by its current facing direction, described by a percentage--how much of current vel is transferred to facing vel per second.

Unlike Drop and Sway, this is consistent at any flight distance...sort of. Because it's tied to the projectile's facing direction, and because the projectile's facing direction *starts* the same as its velocity, this won't have any effect right away. It also becomes stronger the more the projectile's facing direction deviates from its current velocity (this is done with a dot product).

Higher values in this variable make the projectile 'curve' harder toward whatever direction it's tumbling toward.

Aerodynamic effects can be changed by overriding the `DoDrift()` function.

### Stability: double, double
How much the bullet tumbles over time, described by two numbers: peak range, and peak tumble rate per second.

Like with Sway, a random direction is picked--but unlike Sway, that random direction is adjusted every StepMove, to represent the much more chaotic nature of a bullet's tumbling. 

Then, the tumble rate is calculated as `(distance / peakrange) * tumblerate`, much like with Drop and Sway.

The tumbling process can be adjusted by overriding the `DoStability()` function.

### OptRange: double
Bullets can have an Optimal Range--a distance that they can travel without calling DoDrift() or DoStability().

Essentially, the OptRange is subtracted from the bullet's *actual* travel distance; then, DoDrift and DoStability receive `max(calculated_distance,0)`, while DoDrop receives the calculated distance. (This is so that DoDrop has the option of having the bullet rise briefly over the optimal range, to mimic actual ballistics and the effects of zeroing a sight for a longer distance).

The default OptRange of zero means that bullets start dropping and drifting from the moment they're fired, though the first StepMove still happens before the bullet can drift or drop at all (since it happens at distance = 0).

### Distance: double
Not actually a property, but important to think about. The distance the bullet travels affects many other factors, such as how far the bullet will deviate from its current flight path. One of the responsibilities of StepMove() is to increment distance.

### TumbleDmgFactor: double
How much damage can be reduced by based on tumbling. This number is the percentage of damage lost when the bullet is perpendicular to the target.

### BaseDamage : int
The base damage value of the bullet. This is how much damage the bullet does if it hits dead-on.

### Steps: int
How many movement steps the projectile should do each tick. Higher values mean more granular movement, but higher performance impact (theoretically). Default is 4.

### int DamageCalc()
This function uses the bullet's current velocity, as well as the difference between its velocity and its facing direction, to calculate damage. It is assumed that a bullet which is facing directly at the target when it hits will do maximum damage. If you want to alter the damage calculation--say, to account for keyholing--this is the function you should fiddle with.

The standard damage calculation is `basedamage * (1.0 - (facingvector.unit() dot vel.unit() * TumbleDmgFactor))`.

### bool, double StepMove(int stepcount, double dist)
This function is responsible for moving the BallisticProj, and is called multiple times per tick. Each time it is called, it:
- Adjusts the projectile's angle and pitch based on its Stability property, using the `DoStability()` function
- Adjusts the projectile's velocity based on its Sway and Aero properties, using the `DoDrift()` function
- Adjusts the projectile's velocity based on its Drop property and the local gravity, using the `DoDrop()` function
- Performs a hitscan based on the projectile's velocity and the `dist` value
    - If that hitscan hits a `+SHOOTABLE` object that isn't our `target`, call `MobPenCheck()` to decide if the bullet can keep going through that object
    - If that hitscan hits a wall, call `WallPenCheck()` to decide if the bullet can keep going through the wall
- Warp the BallisticProj to the end of the hitscan
- For each item that was hit, call the appropriate damage functions, and adjust the bullet's angle and pitch accordingly
- Return true if the next StepMove should be called, or false if movement processing should end early; either way, return actual length of hitscan

StepMove is called a number of times per Tick(), up to the projectile's Steps--but the projectile will stop processing movement early if it decides that it is stuck inside a creature or wall.

Each time StepMove is called, it is passed a distance value equal to the projectile's current speed, divided by the maximum number of steps. In other words, the projectile theoretically moves `vel.length()` units per tick, but does so in a number of steps, each of which adjusts its velocity (and may lengthen or shorten the overall distance).