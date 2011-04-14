class RPGRules extends GameRules
	config(TitanRPG);

//for debugging, cba to code these up everytime, FALSE by default, can be toggled by "mutate damagelog"
var bool bDamageLog;

var Sound DisgraceAnnouncement, EagleEyeAnnouncement;

var MutTitanRPG RPGMut;
var int PointsPerLevel;
var float LevelDiffExpGainDiv;
var bool bAwardedFirstBlood;

var bool bGameEnded;

//Kills
var class<DamageType> KillDamageType;

//These damage types are simply passed through without any ability, weapon magic or similar being able to scale it
var array<class<DamageType> > DirectDamageTypes;

//These damage types should not have UDamage applied
var array<class<DamageType> > NoUDamageTypes;

/*
	Experience Awards
*/

//Kills
var config float EXP_Frag, EXP_SelfFrag, EXP_TeamFrag, EXP_TypeKill;
var config float EXP_FirstBlood, EXP_KillingSpree[6], EXP_MultiKill[7];
var config float EXP_EndSpree, EXP_CriticalFrag;

//Special kills
var config float EXP_Telefrag, EXP_Headshot;

//Game events
var config float EXP_Win;

/*
	CTF
	EXP_FlagCapFirstTouch - EXP for whomever touched the flag first for the cap.
	EXP_FlagCapAssist - EXP for everyone who held the flag at a point during the cap.
	EXP_FlagCapFinal - EXP for whomever does the actual cap.
	
	EXP_ReturnFriendlyFlag - Return flag which was close to the own base.
	EXP_ReturnEnemyFlag - Return flag which was far from the own base.
	EXP_FlagDenial - Return flag which was very close to the enemy base.
*/
var config float EXP_FlagCapFirstTouch, EXP_FlagCapAssist, EXP_FlagCapFinal;
var config float EXP_ReturnFriendlyFlag, EXP_ReturnEnemyFlag, EXP_FlagDenial;

/*
	BR
	EXP_BallScoreAssist - EXP for everyone who held the ball at a point during the score.
	EXP_BallThrownFinal - EXP for whomever fired the ball into the goal.
	EXP_BallCapFinal - EXP for whomever jumps through the goal.
*/
var config float EXP_BallThrownFinal, EXP_BallCapFinal, EXP_BallScoreAssist;

/*
	DOM
	EXP_DOMScore - EXP for whomever touched the point in the first place.
*/
var config float EXP_DOMScore;

//ONS
var config float EXP_HealPowernode, EXP_ConstructPowernode, EXP_DestroyPowernode, EXP_DestroyConstructingPowernode;
var config float EXP_DamagePowercore;

//AS
var config float EXP_ObjectiveCompleted;

//TODO: Win game, ONS events, CTF events, BR events, AS events, DOM events, Necromancy

//Misc
var config float EXP_Resurrection; //resurrection using the Necromancy combo
var config float EXP_VehicleRepair; //EXP for repairing 1 "HP"

/*
	EXP_Assist - Will be multiplied by the relative time assisted.
*/
var config float EXP_Assist;

//TitanRPG
var config float EXP_Healing; //default damage multiplier for healing teammates (LM will scale this)
var config float EXP_TeamBooster; //EXP per second per healed player

//Multipliers
var config float EXPMul_DestroyVehicle; //you get the XP of a normal kill multiplied by this value
var config float EXPMul_SummonKill; //you get the XP of a normal kill multiplied by this value

//Not yet featured
var config float EXP_HeadHunter, EXP_ComboWhore, EXP_FlakMonkey, EXP_RoadRampage, EXP_Hatrick, EXP_Daredevil;

/*
*/

//Data to allow custom weapon stat entries for "F3" (such as Lightning Rod, Ultima etc)
struct CustomWeaponStatStruct
{
	var class<DamageType> DamageType; //if a kill is done with this damage type...
	var class<Weapon> WeaponClass; //...a kill with this weapon will be tracked
};
var config array<CustomWeaponStatStruct> CustomWeaponStats;

//Necromancy check queue
var config array<string> ResurrectionCombos;

struct NecroCheckStruct
{
	var RPGPlayerReplicationInfo RPRI;
	var int OldComboCount;
	
	var int WaitTicks;
};
var array<NecroCheckStruct> NecroCheck;

static function RPGRules Instance(LevelInfo Level)
{
	local GameRules Rules;

	for(Rules = Level.Game.GameRulesModifiers; Rules != None; Rules = Rules.NextGameRules)
	{
		if(RPGRules(Rules) != None)
			return RPGRules(Rules);
	}
	return None;
}

event PostBeginPlay()
{
	bGameEnded = false;
	SetTimer(Level.TimeDilation, true);

	Super.PostBeginPlay();
}

//checks if the player that owns the specified RPGStatsInv is linked up to anybody and if so shares Amount EXP
//equally between them, otherwise gives it all to the lone player
static function ShareExperience(RPGPlayerReplicationInfo InstigatorRPRI, float Amount)
{
	local LinkGun Head, Link;
	local Controller C;
	local RPGPlayerReplicationInfo RPRI;
	local array<RPGPlayerReplicationInfo> Links;
	local int i;
	
	if(Amount == 0)
		return;
	
	if(InstigatorRPRI.Controller.Pawn == None || InstigatorRPRI.Controller.Pawn.Weapon == None)
	{
		//dead or has no weapon, so can't be linked up
		InstigatorRPRI.AwardExperience(Amount);
	}
	else
	{
		Head = LinkGun(class'Util'.static.GetWeapon(InstigatorRPRI.Controller.Pawn.Weapon));
		if(Head == None)
		{
			// Instigator is not using a Link Gun
			InstigatorRPRI.AwardExperience(Amount);
		}
		else
		{
			//create a list of everyone that should share the EXP
			Links[0] = InstigatorRPRI;
			for(C = InstigatorRPRI.Level.ControllerList; C != None; C = C.NextController)
			{
				if(C.Pawn != None && C.Pawn.Weapon != None)
				{
					Link = LinkGun(class'Util'.static.GetWeapon(C.Pawn.Weapon));
					if(Link != None && Link.LinkedTo(Head))
					{
						RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(C);
						if(RPRI != None)
							Links[Links.length] = RPRI;
					}
				}
			}
			
			// share the experience among the linked players
			Amount /= float(Links.Length);
			for(i = 0; i < Links.Length; i++)
				Links[i].AwardExperience(Amount);
		}
	}
}

/**
	SCORE OBJECTIVE
*/
function ScoreObjective(PlayerReplicationInfo Scorer, int Score)
{
	local RPGPlayerReplicationInfo RPRI;
	
	Super.ScoreObjective(Scorer, Score);
	
	if(Score > 0)
	{
		Log("ScoreObjective" @ Scorer.PlayerName @ Score);
		
		if(Level.Game.IsA('ONSOnslaughtGame'))
		{
			RPRI = class'RPGPlayerReplicationInfo'.static.GetForPRI(Scorer);
		}
		else if(Level.Game.IsA('ASGameInfo'))
		{
			//Assault objective scored
			RPRI = class'RPGPlayerReplicationInfo'.static.GetForPRI(Scorer);
			if(RPRI != None)
				RPRI.AwardExperience(EXP_ObjectiveCompleted);
		}
	}
}

// calculate how much exp does a player get for killing another player of a certain level
function float GetKillEXP(RPGPlayerReplicationInfo KillerRPRI, RPGPlayerReplicationInfo KilledRPRI, optional float Multiplier)
{
	local float XP;
	local float Diff;
	
	if(KilledRPRI != None)
	{
		Log(KillerRPRI.RPGName @ "killed" @ KilledRPRI.RPGName, 'GetKillEXP');
		
		Diff = FMax(0, KilledRPRI.RPGLevel - KillerRPRI.RPGLevel);
		Log("Level difference is" @ Diff, 'GetKillEXP');
		
		if(Diff > 0)
		{
			Diff = (Diff * Diff) / LevelDiffExpGainDiv;
			Log("Post processed difference value is" @ Diff, 'GetKillEXP');
		}
		
		//cap gained exp to enough to get to Killed's level
		if(KilledRPRI.RPGLevel - KillerRPRI.RPGLevel > 0 && Diff > (KilledRPRI.RPGLevel - KillerRPRI.RPGLevel) * KilledRPRI.NeededExp)
		{
			Diff = (KilledRPRI.RPGLevel - KillerRPRI.RPGLevel) * KilledRPRI.NeededExp;
			Log("Capped difference value is" @ Diff, 'GetKillEXP');
		}
		
		Diff = float(int(Diff)); //round

		if(Multiplier > 0)
		{
			Diff *= Multiplier;
			Log("Difference value multiplied by" @ Multiplier @ "is" @ Diff, 'GetKillEXP');
		}
	}
	
	XP = FMax(EXP_Frag, Diff); //at least EXP_Frag
	
	Log("Final XP:" @ XP, 'GetKillEXP');
	return XP;
}

/***************************************************
****************** SCORE KILL **********************
***************************************************/
function ScoreKill(Controller Killer, Controller Killed)
{
	local int x;
	local Inventory Inv, NextInv;
	local vector TossVel, U, V, W;
	local Pawn KillerPawn, KilledPawn;
	local RPGPlayerReplicationInfo KillerRPRI, KilledRPRI;
	local class<Weapon> KillWeaponType;
	
	Super.ScoreKill(Killer, Killed);
	
	//Nobody was killed...
	if(Killed == None)
		return;
	
	//Get Pawns
	KillerPawn = Killer.Pawn;
	KilledPawn = Killed.Pawn;
	
	//Drop artifacts
	if(KilledPawn != None)
	{
		Inv = KilledPawn.Inventory;
		while(Inv != None)
		{
			NextInv = Inv.Inventory;
			if(Inv.IsA('RPGArtifact'))
			{
				TossVel = Vector(KilledPawn.GetViewRotation());
				TossVel = TossVel * ((KilledPawn.Velocity dot TossVel) + 500) + Vect(0,0,200);
				TossVel += VRand() * (100 + Rand(250));
				Inv.Velocity = TossVel;
				KilledPawn.GetAxes(KilledPawn.Rotation, U, V, W);
				Inv.DropFrom(KilledPawn.Location + 0.8 * KilledPawn.CollisionRadius * U - 0.5 * KilledPawn.CollisionRadius * V);
			}
			Inv = NextInv;
		}
	}
	
	//Get RPRIs
	KillerRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killer);
	KilledRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killed);
	
	//Suicide / Self Kill
	if(Killer == Killed)
	{
		if(KillerRPRI != None)
			KillerRPRI.AwardExperience(EXP_SelfFrag);
		
		return;
	}
	
	//Team kill
	if(Killed.SameTeamAs(Killer))
	{
		if(KillerRPRI != None)
			KillerRPRI.AwardExperience(EXP_TeamFrag);
		
		return;
	}
	
	if(Killer.IsA('FriendlyMonsterController') || Killer.IsA('FriendlyTurretController'))
	{
		//A summoned monster or constructed turret killed something
		if(Killer.IsA('FriendlyMonsterController'))
		{
			Killer = FriendlyMonsterController(Killer).Master;
			RegisterWeaponKill(Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, class'DummyWeapon_Monster');
			
			if(Killer.IsA('PlayerController') && Killed.PlayerReplicationInfo != None)
				PlayerController(Killer).ReceiveLocalizedMessage(class'FriendlyMonsterKillerMessage',, Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, KillerPawn);
		}
		else if(Killer.IsA('FriendlyTurretController'))
		{
			Killer = FriendlyTurretController(Killer).Master;
			RegisterWeaponKill(Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, class'DummyWeapon_Turret');

			if(Killer.IsA('PlayerController') && Killed.PlayerReplicationInfo != None)
				PlayerController(Killer).ReceiveLocalizedMessage(class'FriendlyTurretKillerMessage',, Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, KillerPawn);
		}
		
		//Award experience
		KillerRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killer);
		if(KillerRPRI != None)
			KillerRPRI.AwardExperience(GetKillEXP(KillerRPRI, KilledRPRI, EXPMul_SummonKill));
		
		//Add legitimate score
		if(Killer.PlayerReplicationInfo != None)
		{
			Killer.PlayerReplicationInfo.Score += 1.0f;
			
			if(Level.Game.MaxLives > 0)
				Level.Game.CheckScore(Killer.PlayerReplicationInfo); //possibly win the match
		}
		
		return;
	}
	else
	{
		if(Killer.PlayerReplicationInfo != None)
		{
			KillWeaponType = GetDamageWeapon(KillDamageType);
			if(KillWeaponType != None)
				RegisterWeaponKill(Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, KillWeaponType);
		}
	
		//TODO: Adjust adrenaline for lightning rod kills
	
		if(KillerRPRI != None)
		{
			/*
				EXPERIENCE
			*/
			
			//Kill
			if(!Killed.IsA('Bot') || RPGMut.GameSettings.bExpForKillingBots)
				ShareExperience(KillerRPRI, GetKillEXP(KillerRPRI, KilledRPRI));
			
			//Type kill
			if(Killed.IsA('PlayerController') && PlayerController(Killed).bIsTyping)
			{
				Log("TYPE KILL:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_TypeKill);
			}
			
			//Translocator kill
			if(KillDamageType == class'DamTypeTeleFrag')
			{
				Log("TELEFRAG:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_Telefrag);
			}
			
			//Head shot
			if(KillDamageType == class'DamTypeSniperHeadShot' || KillDamageType == class'DamTypeClassicHeadshot')
			{
				Log("HEAD SHOT:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_HeadShot);
			}
			
			//Multi kill
			if(Killer.IsA('UnrealPlayer') && UnrealPlayer(Killer).MultiKillLevel > 0)
			{
				Log("MULTI KILL (" $ string(UnrealPlayer(Killer).MultiKillLevel) $ ":" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_MultiKill[Min(UnrealPlayer(Killer).MultiKillLevel, ArrayCount(EXP_MultiKill))]);
			}
		
			//Spree
			if(
				UnrealPawn(Killer.Pawn) != None &&
				UnrealPawn(Killer.Pawn).spree > 0 &&
				UnrealPawn(Killer.Pawn).spree % 5 == 0
			)
			{
				Log("KILLING SPREE (" $ string(UnrealPawn(Killer.Pawn).spree / 5) $ ":" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_KillingSpree[Min(UnrealPawn(Killer.Pawn).spree / 5, ArrayCount(EXP_KillingSpree))]);
			}
			
			//First blood
			if(
				Killer.PlayerReplicationInfo.Kills == 1 &&
				TeamPlayerReplicationInfo(Killer.PlayerReplicationInfo).bFirstBlood
			)
			{
				Log("FIRST BLOOD:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_FirstBlood);
			}
			
			//End spree
			if(
				UnrealPawn(Killed.Pawn) != None &&
				UnrealPawn(Killed.Pawn).spree > 4
			)
			{
				Log("END SPREE:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_EndSpree);
			}
			
			//Kill flag carrier
			if(Level.Game.IsA('TeamGame') && TeamGame(Level.Game).CriticalPlayer(Killed))
			{
				Log("CRITICAL FRAG:" @ KillerRPRI.RPGName, 'DEBUG');
				KillerRPRI.AwardExperience(EXP_CriticalFrag);
			}
			
			//Notify killer's abilities
			for(x = 0; x < KillerRPRI.Abilities.length; x++)
			{
				if(KillerRPRI.Abilities[x].bAllowed)
					KillerRPRI.Abilities[x].ScoreKill(Killed, KillDamageType);
			}
		}
		
		if(KilledRPRI != None)
		{
			//Notify victim's abilities
			for(x = 0; x < KilledRPRI.Abilities.length; x++)
			{
				if(KilledRPRI.Abilities[x].bAllowed)
					KilledRPRI.Abilities[x].Killed(Killer, KillDamageType);
			}
		}
	}
}

/*
// award EXP based on damage done
function AwardEXPForDamage(Controller InstigatedBy, RPGPlayerReplicationInfo InstRPRI, Pawn injured, float Damage)
{
	local float xp;

	if(
		InstigatedBy != Injured.Controller &&
		InstRPRI != None &&
		injured.IsA('Monster') &&
		injured.Controller != None &&
		!injured.Controller.IsA('FriendlyMonsterController')
	)
	{
		Damage = FMin(Damage, injured.Health);
		xp = RPGMut.GameSettings.ExpForDamageScale * (Damage / injured.HealthMax) * float(Monster(injured).ScoringValue);

		if(xp > 0)
		{
			if(InstigatedBy.IsA('FriendlyMonsterController'))
				InstRPRI.AwardExperience(xp * EXPMul_SummonKill);
			else
				ShareExperience(InstRPRI, xp);
		}
	}
}
*/

//Get exp for damage
function float GetDamageEXP(int Damage, Pawn InstigatedBy, Pawn Injured)
{
	if(
		Damage == 0 ||
		InstigatedBy == Injured ||
		InstigatedBy.Controller.SameTeamAs(Injured.Controller)
	)
	{
		return 0;
	}
	
	if(Injured.IsA('Monster'))
		return RPGMut.GameSettings.ExpForDamageScale * (float(Damage) / Injured.HealthMax) * float(Monster(Injured).ScoringValue);
	
	return 0;
}

/***************************************************
****************** NET DAMAGE **********************
***************************************************/
function int NetDamage(int OriginalDamage, int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
	local RPGWeaponModifier WM;
	local Controller injuredController, instigatorController;
	local RPGPlayerReplicationInfo injuredRPRI, instigatorRPRI;
	local Inventory Inv;
	local int x;

	if(bDamageLog)
	{
		Log("BEGIN", 'RPGDamage');
		Log("OriginalDamage =" @ OriginalDamage, 'RPGDamage');
		Log("Damage =" @ Damage, 'RPGDamage');
		Log("injured =" @ injured, 'RPGDamage');
		Log("instigatedBy =" @ instigatedBy, 'RPGDamage');
		Log("HitLocation =" @ HitLocation, 'RPGDamage');
		Log("Momentum =" @ Momentum, 'RPGDamage');
		Log("DamageType =" @ DamageType, 'RPGDamage');
		Log("---", 'RPGDamage');
	}
	
	//Filter UDamage
	if(
		class'Util'.static.InArray(DamageType, NoUDamageTypes) >= 0 &&
		instigatedBy != None &&
		instigatedBy.HasUDamage()
	)
	{
		OriginalDamage /= 2;
		Damage /= 2;

		if(bDamageLog)
		{
			Log("This damage type should not have UDamage applied!", 'RPGDamage');
			Log("-> OriginalDamage = " $ OriginalDamage, 'RPGDamage');
			Log("-> Damage = " $ Damage, 'RPGDamage');
		}
	}

	//Direct damage types
	if(class'Util'.static.InArray(DamageType, DirectDamageTypes) >= 0)
	{
		if(bDamageLog)
		{
			Log("This is a direct damage type and will not be processed further by RPG.", 'RPGDamage');
			Log("END", 'RPGDamage');
		}
		
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType); //pass-through
	}
	
	//Let other rules modify damage
	Damage = Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	
	if(bDamageLog)
		Log("After Super call: Damage =" @ Damage $ ", Momentum =" @ Momentum, 'RPGDamage');
	
	//Get info
	
	//TODO: Friendly monster / turret
	//TODO: Vehicles
	
	injuredController = injured.Controller;
	injuredRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(injuredController);

	instigatorController = instigatedBy.Controller;
	instigatorRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(instigatorController);
	
	if(bDamageLog)
	{
		Log("instigatorController =" @ instigatorController, 'RPGDamage');
		
		if(instigatorRPRI != None)
			Log("instigatorRPRI =" @ instigatorRPRI.RPGName, 'RPGDamage');
		else
			Log("instigatorRPRI = None");
	
		Log("injuredController =" @ injuredController, 'RPGDamage');
		
		if(injuredRPRI != None)
			Log("injuredRPRI =" @ injuredRPRI.RPGName, 'RPGDamage');
		else
			Log("injuredRPRI = None");
	}
	
	/*
		ACTIVE DAMAGE MODIFICATION
	*/
	
	//Abilities
	if(instigatorRPRI != None)
	{
		for(x = 0; x < instigatorRPRI.Abilities.length; x++)
		{
			if(instigatorRPRI.Abilities[x].bAllowed)
				instigatorRPRI.Abilities[x].AdjustTargetDamage(Damage, OriginalDamage, injured, instigatedBy, HitLocation, Momentum, DamageType);
		}
	}
	
	//RPGWeapon
	if(RPGWeapon(instigatedBy.Weapon) != None)
		RPGWeapon(instigatedBy.Weapon).RPGAdjustTargetDamage(Damage, OriginalDamage, injured, HitLocation, Momentum, DamageType);
	
	//Weapon modifier
	WM = class'RPGWeaponModifier'.static.GetFor(instigatedBy.Weapon);
	if(WM != None)
		WM.AdjustTargetDamage(Damage, OriginalDamage, injured, HitLocation, Momentum, DamageType);
	
	//Active artifacts
	for(Inv = instigatedBy.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Inv.IsA('RPGArtifact') && RPGArtifact(Inv).bActive)
			RPGArtifact(Inv).AdjustTargetDamage(Damage, OriginalDamage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}
	
	//TODO: Vehicle magic
	
	/*
		PASSIVE DAMAGE MODIFICATION
	*/
	
	//Abilities
	if(injuredRPRI != None)
	{
		for(x = 0; x < instigatorRPRI.Abilities.length; x++)
		{
			if(instigatorRPRI.Abilities[x].bAllowed)
				instigatorRPRI.Abilities[x].AdjustPlayerDamage(Damage, OriginalDamage, injured, instigatedBy, HitLocation, Momentum, DamageType);
		}
	}
	
	//RPGWeapon
	if(RPGWeapon(injured.Weapon) != None)
		RPGWeapon(injured.Weapon).RPGAdjustPlayerDamage(Damage, OriginalDamage, instigatedBy, HitLocation, Momentum, DamageType);
	
	//Weapon modifier
	WM = class'RPGWeaponModifier'.static.GetFor(injured.Weapon);
	if(WM != None)
		WM.AdjustPlayerDamage(Damage, OriginalDamage, instigatedBy, HitLocation, Momentum, DamageType);
	
	//Active artifacts
	for(Inv = injured.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		if(Inv.IsA('RPGArtifact') && RPGArtifact(Inv).bActive)
			RPGArtifact(Inv).AdjustPlayerDamage(Damage, OriginalDamage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}
	
	//TODO: Vehicle magic
	
	/*
	*/
	
	//Experience
	if(instigatorRPRI != None)
	{
		ShareExperience(instigatorRPRI, GetDamageEXP(Damage, instigatedBy, Injured));
	}
	
	//Done
	if(bDamageLog)
	{
		Log("Final Damage =" @ Damage $ ", Momentum =" @ Momentum, 'RPGDamage');
		Log("END", 'RPGDamage');
	}
	return Damage;
}

/*
function int NetDamage(int OriginalDamage, int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
	local RPGPlayerReplicationInfo InjuredRPRI, InstRPRI, RPRI;
	local int x;
	local bool bZeroDamage;
	local Controller InjuredController, InstigatorController;
	local ONSVehicle V;
	local ONSWeaponPawn WP, InjuredWeaponPawn, InstigatorWeaponPawn; //"side turret"
	local Inventory Inv;
	local RPGArtifact A;
	local VehicleMagic VM;
	local AbilityVehicleEject Eject;
	local RPGWeapon RW;
	
	if(bDamageLog)
	{
		Log("=== RPGRules.NetDamage BEGIN ===");
		Log("OriginalDamage = " $ OriginalDamage);
		Log("Damage = " $ Damage);
		Log("injured = " $ injured);
		Log("instigatedBy = " $ instigatedBy);
		Log("HitLocation = " $ HitLocation);
		Log("Momentum = " $ Momentum);
		Log("DamageType = " $ DamageType);
		Log("");
	}
	
	//Filter UDamage if desired for this damage type
	if(
		class'Util'.static.InArray(DamageType, NoUDamageTypes) >= 0 &&
		instigatedBy != None &&
		instigatedBy.HasUDamage()
	)
	{
		OriginalDamage = int(float(OriginalDamage) / (2.f * instigatedBy.DamageScaling));
		Damage = int(float(Damage) / (2.f * instigatedBy.DamageScaling));
		
		if(bDamageLog)
		{
			Log("DEBUG: This damage type should not have UDamage applied!");
			Log("DEBUG: OriginalDamage = " $ OriginalDamage);
			Log("DEBUG: Damage = " $ Damage);
		}
	}
	
	//Direct damage types should not be processed by RPG
	if(class'Util'.static.InArray(DamageType, DirectDamageTypes) >= 0)
	{
		if(bDamageLog)
		{
			Log("DEBUG: This is a direct damage type and will not be processed further by RPG!");
			Log("=== RPGRules.NetDamage END ===");
		}
		
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType); //pass-through
	}

	//Don't do anything to friendly monsters
	if(
		injured.IsA('Monster') &&
		FriendlyMonsterController(injured.Controller) != None &&
		instigatedBy != None &&
		instigatedBy.Controller != None &&
		instigatedBy.Controller.SameTeamAs(injured.Controller)
		)
	{
		if(bDamageLog)
		{
			Log("ZERO: Do not hurt friendly monsters!");
			Log("=== RPGRules.NetDamage END ===");
		}
	
		return 0;
	}
		
	//Pass through damage done by a monster to another monster
	if(Monster(injured) != None && Monster(instigatedBy) != None)
	{
		if(bDamageLog)
		{
			Log("SKIP: Damage done to a monster by another monster!");
			Log("=== RPGRules.NetDamage END ===");
		}
	
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}

	//Let Ejector Seat decide whether or not to ignore this damage type
	if(!injured.IsA('Vehicle'))
	{
		RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(injured.Controller);
		if(RPRI != None)
		{
			Eject = AbilityVehicleEject(RPRI.GetOwnedAbility(class'AbilityVehicleEject'));
			if(Eject != None && Eject.HasJustEjected() && Eject.ProtectsAgainst(DamageType))
			{
				if(bDamageLog)
				{
					Log("ZERO: Damage was nullified by Ejector Seat!");
					Log("=== RPGRules.NetDamage END ===");
				}
				
				return 0;
			}
		}
	}
	
	//Check whether injured is a vehicle, if so, browse through the side turrets and see whether it is manned
	//Enables effects to work in/on vehicle side turrets
	V = ONSVehicle(injured);
	if(V != None && V.Controller == None)
	{
		for(x = 0; x < V.WeaponPawns.Length; x++)
		{
			WP = V.WeaponPawns[x];
			if(WP != None && WP.Controller != None)
			{
				InjuredWeaponPawn = WP;
				break;
			}
		}
	}
	
	//Same for instigator
	V = ONSVehicle(instigatedBy);
	if(V != None && V.Controller == None)
	{
		for(x = 0; x < V.WeaponPawns.Length; x++)
		{
			WP = V.WeaponPawns[x];
			if(WP != None && WP.Controller != None)
			{
				InstigatorWeaponPawn = WP;
				break;
			}
		}
	}
	
	if(bDamageLog)
	{
		Log("DEBUG: InstigatorWeaponPawn = " $ InjuredWeaponPawn);
		Log("DEBUG: InjuredWeaponPawn = " $ InjuredWeaponPawn);
	}

	if(
		injured == None ||
		instigatedBy == None ||
		(injured.Controller == None && InjuredWeaponPawn == None) ||
		(instigatedBy.Controller == None && InstigatorWeaponPawn == None)
	)
	{
		if(bDamageLog)
		{
			Log("SKIP: Not enough information for RPG processing!");
			Log("=== RPGRules.NetDamage END ===");
		}
	
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}

	InjuredController = injured.Controller;
	if(InjuredController == None)
		InjuredController = InjuredWeaponPawn.Controller;
		
	InstigatorController = instigatedBy.Controller;
	if(InstigatorController == None)
		InstigatorController = InstigatorWeaponPawn.Controller;
		
	if(bDamageLog)
	{
		Log("DEBUG: InjuredController = " $ InjuredController);
		Log("DEBUG: InstigatorController = " $ InstigatorController);
	}

	if(Damage <= 0)
	{
		Damage = Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
		if(Damage < 0)
		{
			if(bDamageLog)
			{
				Log("SKIP: Negative damage!");
				Log("=== RPGRules.NetDamage END ===");
			}
		
			return Damage;
		}
		else if (Damage == 0) //for zero damage, still process abilities/magic weapons so effects relying on hits instead of damage still work
		{
			if(bDamageLog)
				Log("INFO: Zero damage!");
		
			bZeroDamage = true;
		}
	}
	
	InstRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(InstigatorController);
	InjuredRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(InjuredController);
	
	if(bDamageLog)
	{
		Log("DEBUG: InstRPRI = " $ InstRPRI);
		Log("DEBUG: InjuredRPRI = " $ InjuredRPRI);
	}
	
	if(Monster(instigatedBy) == None && InstRPRI == None)
	{
		//This should never happen
		Warn("InstRPRI not found for " $ instigatedBy.GetHumanReadableName() $ " (" $ instigatedBy $ ")");
		
		if(default.bDamageLog)
			Log("=== RPGRules.NetDamage END ===");
		
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}
	
	if(Monster(injured) == None && TurretController(InjuredController) == None && InjuredRPRI == None)
	{
		//This should never happen
		Warn("InjuredRPRI not found for " $ injured.GetHumanReadableName() $ " (" $ injured $ ")");
		
		if(default.bDamageLog)
			Log("=== RPGRules.NetDamage END ===");
		
		return Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
	}

	//headshot bonus EXP
	if(
		InstRPRI != None &&
		(DamageType == class'DamTypeSniperHeadShot' || DamageType == class'DamTypeClassicHeadshot') &&
		!InstigatorController.SameTeamAs(InjuredController))
	{
		if(default.bDamageLog)
			Log("DEBUG: HEADSHOT!!");
		
		InstRPRI.AwardExperience(EXP_HeadShot);
	}
	
	if(bDamageLog)
		Log("DEBUG: Processing damage...");

	if(InstRPRI != None)
		Damage += int(float(Damage) * float(InstRPRI.Attack) * 0.005);
	
	if(bDamageLog)
		Log("DEBUG: After instigator's damage bonus: Damage = " $ Damage);
		
	if(InjuredRPRI != None)
		Damage -= int(float(Damage) * float(InjuredRPRI.Defense) * 0.005);
		
	if(bDamageLog)
		Log("DEBUG: After injured's damage reduction: Damage = " $ Damage);

	if(Damage < 1 && !bZeroDamage)
		Damage = 1;
		
	//if this is weapon damage done by an RPGWeapon, let it modify the damage
	if(ClassIsChildOf(DamageType, class'WeaponDamageType'))
	{
		RW = RPGWeapon(class'Util'.static.TraceBackWeapon(InstigatedBy, class<WeaponDamageType>(DamageType)));
		if(RW != None)
		{
			RW.RPGAdjustTargetDamage(Damage, OriginalDamage, Injured, HitLocation, Momentum, DamageType);

			if(bDamageLog)
				Log("DEBUG: After instigator's WEAPON " $ RW.ItemName $ " RPGAdjustTargetDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
		}
	}
	bZeroDamage = bZeroDamage || Damage == 0;

	//Instigator active artifacts, active damage scaling -pd
	for(Inv = instigatedBy.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		A = RPGArtifact(Inv);
		
		if(A != None && A.bActive)
		{
			A.AdjustTargetDamage(Damage, Injured, HitLocation, Momentum, DamageType);
		
			if(bDamageLog)
				Log("DEBUG: After instigator's active ARTIFACT " $ A.ItemName $ " AdjustTargetDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
		}
	}
	bZeroDamage = bZeroDamage || Damage == 0;
	
	//Instigator's vehicle magic -pd
	VM = class'VehicleMagic'.static.FindFor(instigatedBy);
	if(VM != None)
	{
		VM.AdjustTargetDamage(Damage, Injured, HitLocation, Momentum, DamageType);

		if(bDamageLog)
			Log("DEBUG: After instigator's active VEHICLE MAGIC " $ VM.MagicName $ " AdjustTargetDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
	}
	bZeroDamage = bZeroDamage || Damage == 0;

	//Instigator abilities
	if(InstRPRI != None)
	{
		for(x = 0; x < InstRPRI.Abilities.length; x++)
		{
			if(InstRPRI.Abilities[x].bAllowed)
				InstRPRI.Abilities[x].HandleDamage(Damage, injured, instigatedBy, Momentum, DamageType, true);
		
			if(bDamageLog)
				Log("DEBUG: After instigator's ABILITY " $ InstRPRI.Abilities[x].GetName() $ " HandleDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
		}
	}
	bZeroDamage = bZeroDamage || Damage == 0;

	//Injured weapon magic
	if(RPGWeapon(injured.Weapon) != None)
	{
		RPGWeapon(injured.Weapon).RPGAdjustPlayerDamage(Damage, OriginalDamage, instigatedBy, HitLocation, Momentum, DamageType);
		
		if(bDamageLog)
			Log("DEBUG: After injured's WEAPON " $ RPGWeapon(injured.Weapon).ItemName $ " RPGAdjustPlayerDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
	}
	bZeroDamage = bZeroDamage || Damage == 0;

	//Injured active artifacts, passive damage scaling -pd
	for(Inv = Injured.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		A = RPGArtifact(Inv);
		
		if(A != None && A.bActive)
		{
			A.AdjustPlayerDamage(Damage, instigatedBy, HitLocation, Momentum, DamageType);
			
			if(bDamageLog)
				Log("DEBUG: After injured's active ARTIFACT " $ A.ItemName $ " AdjustPlayerDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);
		}
	}
	bZeroDamage = bZeroDamage || Damage == 0;
	
	//Injured vehicle magic -pd
	VM = class'VehicleMagic'.static.FindForAnyPassenger(Injured);
	if(VM != None)
	{
		VM.AdjustPlayerDamage(Damage, instigatedBy, HitLocation, Momentum, DamageType);
	
		if(bDamageLog)
			Log("DEBUG: After injured's active VEHICLE MAGIC " $ VM.MagicName $ " AdjustPlayerDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);	
	}
	bZeroDamage = bZeroDamage || Damage == 0;
	
	//Injured abilities
	if(InjuredRPRI != None)
	{
		for(x = 0; x < InjuredRPRI.Abilities.length; x++)
		{
			if(InjuredRPRI.Abilities[x].bAllowed)
				InjuredRPRI.Abilities[x].HandleDamage(Damage, injured, instigatedBy, Momentum, DamageType, false);
		
			if(bDamageLog)
				Log("DEBUG: After injured's ABILITY " $ InjuredRPRI.Abilities[x].GetName() $ " HandleDamage: Damage = " $ Damage $ ", Momentum = " $ Momentum);	
		}
	}
	bZeroDamage = bZeroDamage || Damage == 0;
	
	if(bDamageLog)
		Log("=== RPGRules.NetDamage END ===");

	//EXP for damage
	if(bZeroDamage || Damage < 0)
	{
		Damage = 0;
		return 0;
	}
	else
	{
		//retrieve actual damage
		Damage = Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
		
		//xp for damage
		if(InstRPRI != None)
		{
			AwardEXPForDamage(InstigatorController, InstRPRI, injured, Damage);
		}
		else if(InstigatorController.IsA('FriendlyMonsterController'))
		{
			InstRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(FriendlyMonsterController(InstigatorController).Master);
			if(InstRPRI != None)
				AwardEXPForDamage(InstigatorController, InstRPRI, injured, Damage);
		}

		return Damage;
	}
}
*/

function bool OverridePickupQuery(Pawn Other, Pickup item, out byte bAllowPickup)
{
	local RPGPlayerReplicationInfo RPRI;
	local int x;

	//increase value of ammo pickups based on Max Ammo stat
	if(Other.Controller != None)
	{
		RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Other.Controller);
		if (RPRI != None)
		{
			if (Ammo(item) != None)
				Ammo(item).AmmoAmount = int(Ammo(item).default.AmmoAmount * (1.0 + float(RPRI.AmmoMax) / 100.f));

			for (x = 0; x < RPRI.Abilities.length; x++)
			{
				if(RPRI.Abilities[x].bAllowed)
				{
					if(RPRI.Abilities[x].OverridePickupQuery(Other, item, bAllowPickup))
						return true;
				}
			}
		}
	}

	return Super.OverridePickupQuery(Other, item, bAllowPickup);
}

function bool PreventDeath(Pawn Killed, Controller Killer, class<DamageType> damageType, vector HitLocation)
{
	local Inventory Inv;
	local Weapon W;
	local RPGWeapon RW;
	local bool bAlreadyPrevented;
	local int x;
	local Controller KilledController;
	local Pawn KilledVehicleDriver;
	local RPGPlayerReplicationInfo KillerRPRI, KilledRPRI;
	local AbilityVehicleEject EjectorSeat;
	local ArtifactDoubleModifier DoubleMod;
	
	KillDamageType = damageType;
	
	if(bGameEnded)
		return Super.PreventDeath(Killed, Killer, damageType, HitLocation);
	
	//FIXME hotfix, must find a better solution
	DoubleMod = ArtifactDoubleModifier(Killed.FindInventoryType(class'ArtifactDoubleModifier'));
	if(DoubleMod != None && DoubleMod.bActive)
		DoubleMod.GotoState('');
	
	if((PlayerController(Killer) != None || Bot(Killer) != None) && damageType != None && Killer != Killed.Controller)
	{
		if(damageType == class'DamTypeTeleFrag' || damageType == class'DamTypeTeleFragged')
		{
			if(PlayerController(Killer) != None)
			{
				PlayerController(Killer).PlayAnnouncement(EagleEyeAnnouncement, 1, true);
				PlayerController(Killer).ReceiveLocalizedMessage(class'EagleEyeMessage');
			}
			if(PlayerController(Killed.Controller) != None)
			{
				PlayerController(Killed.Controller).PlayAnnouncement(DisgraceAnnouncement, 1, true);
				PlayerController(Killed.Controller).ReceiveLocalizedMessage(class'DisgraceMessage');
			}
		}
	}

	bAlreadyPrevented = Super.PreventDeath(Killed, Killer, damageType, HitLocation);

	if (Killed.Controller != None)
		KilledController = Killed.Controller;
	else if (Killed.DrivenVehicle != None && Killed.DrivenVehicle.Controller != None)
		KilledController = Killed.DrivenVehicle.Controller;

	if (KilledController != None)
		KilledRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(KilledController);

	if(Vehicle(Killed) != None)
		KilledVehicleDriver = Vehicle(Killed).Driver;

	if (KilledRPRI != None)
	{
		if(Killed.SelectedItem != None)
			KilledRPRI.LastSelectedPowerupType = Killed.SelectedItem.class;
		else
			KilledRPRI.LastSelectedPowerupType = None;
		
		//detect whether this player switched teams
		if(Level.Game.bTeamGame && KilledRPRI.PRI.Team.TeamIndex != KilledRPRI.Team)
		{
			KilledRPRI.bTeamChanged = true; //allow RPRI to react on spawn
			
			if(KilledVehicleDriver != None)
				Inv = KilledVehicleDriver.Inventory;
			else
				Inv = Killed.Inventory;
			
			while(Inv != None)
			{
				W = Weapon(Inv);
				if(W != None && class'AbilityDenial'.static.CanSaveWeapon(W))
				{
					RW = RPGWeapon(W);
					if(RW != None)
						KilledRPRI.QueueWeapon(RW.ModifiedWeapon.class, RW.class, RW.Modifier);
					else
						KilledRPRI.QueueWeapon(W.class, None, 0);
				}

				Inv = Inv.Inventory;
			}
			
			return false; //cannot save from a team switch
		}
		else
		{
			//FIXME Pawn should probably still call PreventDeath() in cases like this, but it might be wiser to ignore the value
			if (!KilledController.bPendingDelete && (KilledController.PlayerReplicationInfo == None || !KilledController.PlayerReplicationInfo.bOnlySpectator))
			{
				for(x = 0; x < KilledRPRI.Abilities.length; x++)
				{
					if(KilledRPRI.Abilities[x].bAllowed)
					{
						if(KilledRPRI.Abilities[x].PreventDeath(Killed, Killer, damageType, HitLocation, bAlreadyPrevented))
							bAlreadyPrevented = true;
					}
				}
			}
		}
	}

	if(bAlreadyPrevented)
	{
		return true;
	}
	else //yes, ELSE. because vehicle ejection doesn't actually save the victim (the vehicle)
	{
		if(
			Killer != None &&
			Killer != KilledController &&
			KilledVehicleDriver != None)
		{
			KilledRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(KilledController);
			if (KilledRPRI == None)
			{
				Log("KilledRPRI not found for " $ Killed.GetHumanReadableName(), 'TitanRPG');
				return true;
			}
			
			EjectorSeat = AbilityVehicleEject(KilledRPRI.GetOwnedAbility(class'AbilityVehicleEject'));
			if(EjectorSeat != None && EjectorSeat.HasJustEjected())
			{
				//get data
				KillerRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killer);
				if (KillerRPRI == None)
				{
					Log("KillerRPRI not found for " $ Killer.GetHumanReadableName(), 'TitanRPG');
					return true;
				}

				ShareExperience(KillerRPRI,
					GetKillEXP(KillerRPRI, KilledRPRI, EXPMul_DestroyVehicle));

				KillerRPRI.PRI.Score += 1.f; //add a game point
				
				//reset killing spree for ejected player
				if(KilledVehicleDriver.GetSpree() > 4)
				{
					Killer.AwardAdrenaline(DeathMatch(Level.Game).ADR_MajorKill);
					ShareExperience(KillerRPRI, EXP_EndSpree);
					DeathMatch(Level.Game).EndSpree(Killer, KilledController);
				}
				
				if(KilledVehicleDriver.IsA('UnrealPawn'))
					UnrealPawn(KilledVehicleDriver).spree = 0;
			}
		}
	}
	
	if((damageType.default.bCausedByWorld || damageType == class'DamTypeTeleFrag') && Killed.Health > 0)
	{
		//if this damagetype is an instant kill that bypasses Pawn.TakeDamage() and calls Pawn.Died() directly
		//then we need to award EXP by damage for the rest of the monster's health
		//TODO: AwardEXPForDamage(Killer, class'RPGPlayerReplicationInfo'.static.GetFor(Killer), Killed, Killed.Health);
	}

	//Yet Another Invasion Hack - Invasion doesn't call ScoreKill() on the GameRules if a monster kills something
	//This one's so bad I swear I'm fixing it for a patch
	if(int(Level.EngineVersion) < 3190 && Level.Game.IsA('Invasion') && KilledController != None && MonsterController(Killer) != None)
	{
		if (KilledController.PlayerReplicationInfo != None)
			KilledController.PlayerReplicationInfo.bOutOfLives = true;

		ScoreKill(Killer, KilledController);
	}
	
	//unless another GameRules decides to prevent death, this is certain death
	if(KillerRPRI == None)
		KillerRPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killer);
	
	if(KillerRPRI != None)
	{
		KillerRPRI.AboutToKill = Killed.Controller;
		KillerRPRI.KillingDamType = damageType;
		KillerRPRI.AdrenalineBeforeKill = Killer.Adrenaline;
	}

	return false;
}

function bool PreventSever(Pawn Killed, name boneName, int Damage, class<DamageType> DamageType)
{
	local RPGPlayerReplicationInfo RPRI;
	local int x;

	if (Killed.Controller != None)
	{
		RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Killed.Controller);
		if (RPRI != None)
		{
			for (x = 0; x < RPRI.Abilities.length; x++)
			{
				if(RPRI.Abilities[x].bAllowed)
				{
					if(RPRI.Abilities[x].PreventSever(Killed, boneName, Damage, DamageType))
						return true;
				}
			}
		}
	}

	return Super.PreventSever(Killed, boneName, Damage, DamageType);
}

function Timer()
{
	local RPGPlayerReplicationInfo RPRI;
	local Controller C;

	if(Level.Game.bGameEnded)
	{
		//Grant exp for win
		if(EXP_Win > 0)
		{
			if(TeamInfo(Level.Game.GameReplicationInfo.Winner) != None)
			{
				for (C = Level.ControllerList; C != None; C = C.NextController)
				{
					if (C.PlayerReplicationInfo != None && C.PlayerReplicationInfo.Team == Level.Game.GameReplicationInfo.Winner)
					{
						RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(C);
						if (RPRI != None)
							RPRI.AwardExperience(EXP_Win);
					}
				}
			}
			else if (PlayerReplicationInfo(Level.Game.GameReplicationInfo.Winner) != None
				  && Controller(PlayerReplicationInfo(Level.Game.GameReplicationInfo.Winner).Owner) != None )
			{
				RPRI = class'RPGPlayerReplicationInfo'.static.GetForPRI(PlayerReplicationInfo(Level.Game.GameReplicationInfo.Winner));
				if (RPRI != None)
					RPRI.AwardExperience(EXP_Win);
			}
		}
		
		RPGMut.EndGame();
		SetTimer(0, false);
	}
}

function bool HandleRestartGame()
{
	return Super.HandleRestartGame();
}

static function RegisterWeaponKill(PlayerReplicationInfo Killer, PlayerReplicationInfo Victim, class<Weapon> WeaponClass)
{
	local int i;
	local bool bFound;
	local TeamPlayerReplicationInfo TPRI;
	local TeamPlayerReplicationInfo.WeaponStats NewWeaponStats;
	
	if(WeaponClass == None)
		return;

	//kill for the killer
	TPRI = TeamPlayerReplicationInfo(Killer);
	if(TPRI != None)
	{
		bFound = false;
		for (i = 0; i < TPRI.WeaponStatsArray.Length; i++ )
		{
			if(TPRI.WeaponStatsArray[i].WeaponClass == WeaponClass)
			{
				TPRI.WeaponStatsArray[i].Kills++;
				bFound = true;
				break;
			}
		}

		if(!bFound)
		{
			NewWeaponStats.WeaponClass = WeaponClass;
			NewWeaponStats.Kills = 1;
			NewWeaponStats.Deaths = 0;
			NewWeaponStats.DeathsHolding = 0;
			TPRI.WeaponStatsArray[TPRI.WeaponStatsArray.Length] = NewWeaponStats;
		}
	}
	
	//death for the victim
	TPRI = TeamPlayerReplicationInfo(Victim);
	if(TPRI != None)
	{
		bFound = false;
		for (i = 0; i < TPRI.WeaponStatsArray.Length; i++ )
		{
			if(TPRI.WeaponStatsArray[i].WeaponClass == WeaponClass)
			{
				TPRI.WeaponStatsArray[i].Deaths++;
				bFound = true;
				break;
			}
		}

		if(!bFound)
		{
			NewWeaponStats.WeaponClass = WeaponClass;
			NewWeaponStats.Kills = 0;
			NewWeaponStats.Deaths = 1;
			NewWeaponStats.DeathsHolding = 0;
			TPRI.WeaponStatsArray[TPRI.WeaponStatsArray.Length] = NewWeaponStats;
		}
	}
}

static function bool IsResurrectionCombo(string ComboName)
{
	local int i;
	
	for(i = 0; i < default.ResurrectionCombos.Length; i++)
	{
		if(InStr(ComboName, default.ResurrectionCombos[i]) >= 0)
			return true;
	}
	
	return false;
}

function class<Weapon> GetDamageWeapon(class<DamageType> DamageType)
{
	local int i;
	
	for(i = 0; i < CustomWeaponStats.Length; i++)
	{
		if(CustomWeaponStats[i].DamageType == DamageType)
			return CustomWeaponStats[i].WeaponClass;
	}
	return None;
}

defaultproperties
{
	bDamageLog=False

	DisgraceAnnouncement=Sound'<? echo($packageName); ?>.TranslocSounds.Disgrace'
	EagleEyeAnnouncement=Sound'<? echo($packageName); ?>.TranslocSounds.EagleEye'
	DirectDamageTypes(0)=class'DamTypeEmo'
	DirectDamageTypes(1)=class'DamTypePoison'
	DirectDamageTypes(2)=class'DamTypeRetaliation'
	DirectDamageTypes(3)=class'DamTypeFatality'
	NoUDamageTypes(0)=class'DamTypeRetaliation'
	
	//former RPGGameStats
	CustomWeaponStats(0)=(DamageType=Class'DamTypeTitanUltima',WeaponClass=Class'DummyWeapon_Ultima')
	CustomWeaponStats(1)=(DamageType=Class'DamTypeUltima',WeaponClass=Class'DummyWeapon_Ultima')
	CustomWeaponStats(2)=(DamageType=Class'DamTypeLightningRod',WeaponClass=Class'DummyWeapon_LightningRod')
	CustomWeaponStats(3)=(DamageType=Class'DamTypeCounterShove',WeaponClass=Class'DummyWeapon_CounterShove')
	CustomWeaponStats(4)=(DamageType=Class'DamTypePoison',WeaponClass=Class'DummyWeapon_Poison')
	CustomWeaponStats(5)=(DamageType=Class'DamTypeRetaliation',WeaponClass=Class'DummyWeapon_Retaliation')
	CustomWeaponStats(6)=(DamageType=Class'DamTypeSelfDestruct',WeaponClass=Class'DummyWeapon_SelfDestruct')
	CustomWeaponStats(7)=(DamageType=Class'DamTypeEmo',WeaponClass=Class'DummyWeapon_Emo')
	CustomWeaponStats(8)=(DamageType=Class'DamTypeMegaExplosion',WeaponClass=Class'DummyWeapon_MegaBlast')
	CustomWeaponStats(9)=(DamageType=Class'DamTypeRepulsion',WeaponClass=Class'DummyWeapon_Repulsion')
	CustomWeaponStats(10)=(DamageType=Class'DamTypeVorpal',WeaponClass=Class'DummyWeapon_Vorpal')

	//Kills
	EXP_Frag=1.00
	EXP_SelfFrag=0.00 //-1.00 really, but we don't want to lose exp here
	EXP_TeamFrag=0.00
	EXP_TypeKill=0.00
	
	EXP_EndSpree=5.00
	EXP_CriticalFrag=3.00
	
	EXP_FirstBlood=5.00
	EXP_KillingSpree(0)=5.00
	EXP_KillingSpree(1)=5.00
	EXP_KillingSpree(2)=5.00
	EXP_KillingSpree(3)=5.00
	EXP_KillingSpree(4)=5.00
	EXP_KillingSpree(5)=5.00
	EXP_MultiKill(0)=5.00
	EXP_MultiKill(1)=5.00
	EXP_MultiKill(2)=5.00
	EXP_MultiKill(3)=5.00
	EXP_MultiKill(4)=5.00
	EXP_MultiKill(5)=5.00
	EXP_MultiKill(6)=5.00
	
	//Special kills
	EXP_Telefrag=1.00
	EXP_Headshot=1.00

	//Game events
	EXP_Win=30
	
	EXP_HealPowernode=1.00
	EXP_ConstructPowernode=2.50
	EXP_DestroyPowernode=5.00
	EXP_DestroyConstructingPowernode=0.16
	
	EXP_DamagePowercore=0.50 //experience for 1% damage

	EXP_ReturnFriendlyFlag=3.00
	EXP_ReturnEnemyFlag=5.00
	EXP_FlagDenial=7.00

	EXP_FlagCapFirstTouch=5.00
	EXP_FlagCapAssist=5.00
	EXP_FlagCapFinal=5.00
	
	EXP_ObjectiveCompleted=1.00
	
	EXP_BallThrownFinal=5.00
	EXP_BallCapFinal=10.00
	EXP_BallScoreAssist=5.00
	
	EXP_DOMScore=5.00
	
	//TitanRPG
	EXP_Healing=0.01
	EXP_TeamBooster=0.10 //per second per healed player (excluding yourself)
	
	//Misc
	EXP_Resurrection=50.00 //experience for resurrecting another player using the Necromancy combo
	EXP_VehicleRepair=0.005 //experience for repairing one "health point"
	EXP_Assist=15.00 //Score Assist
	
	//Multipliers
	EXPMul_DestroyVehicle=0.67
	EXPMul_SummonKill=0.67
	
	//Not yet featured
	EXP_HeadHunter=10.00
	EXP_ComboWhore=10.00
	EXP_FlakMonkey=10.00
	EXP_RoadRampage=10.00
	EXP_Hatrick=10.00
	
	//Resurrection
	ResurrectionCombos(0)="ComboNecro"
	ResurrectionCombos(1)="ComboRevival"
}
