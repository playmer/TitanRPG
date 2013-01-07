class Weapon_MagicNullifier extends RPGWeapon
	HideDropDown
	CacheExempt;
	
var localized string MagicNullText;

simulated function string GetWeaponNameExtra()
{
	local string text;
	
	text = Super.GetWeaponNameExtra();
	
	if(text != "")
		text $= ", ";
	
	text $= MagicNullText;
	
	return text;
}

function bool AllowEffect(class<RPGEffect> EffectClass, Controller Causer, float Duration, float Modifier)
{
	if(
		EffectClass == class'Effect_Freeze' ||
		EffectClass == class'Effect_Knockback' ||
		EffectClass == class'Effect_NullEntropy' ||
		EffectClass == class'Effect_Poison' ||
		EffectClass == class'Effect_Vorpal'
	)
	{
		Identify();
		return false;
	}
	
	return true;
}

defaultproperties
{
	MagicNullText="nullifies harmful magic weapon effects"
	bCanHaveZeroModifier=True
	DamageBonus=0.050000
	MinModifier=4
	MaxModifier=6
	ModifierOverlay=Shader'AW-2k4XP.Weapons.ShockShieldShader'
	PatternPos="Magic Nullifying $W"
	//AI
	CountersMagic(0)=class'Weapon_Freeze'
	CountersMagic(1)=class'Weapon_NullEntropy'
	CountersMagic(2)=class'Weapon_Poison'
	CountersMagic(3)=class'Weapon_Knockback'
	AIRatingBonus=0.025000
}