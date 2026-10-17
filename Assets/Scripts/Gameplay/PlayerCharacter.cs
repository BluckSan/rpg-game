using UnityEngine;

namespace RPG
{
    /// <summary>Здоровье, мана, опыт и уровни игрока. Пересчитывает характеристики при изменениях.</summary>
    public class PlayerCharacter : MonoBehaviour
    {
        public static PlayerCharacter Instance;
        public CharacterData Data;
        public StatBlock Stats;
        public float Hp, Mp;
        public bool Dead => Hp <= 0;
        public CharacterVisual Visual;

        // временные эффекты
        public float rageTimer, shieldTimer;
        public float RageMult => rageTimer > 0 ? 1.5f : 1f;

        public event System.Action OnChanged;

        public void Init(CharacterData d)
        {
            Instance = this;
            Data = d;
            Recalc(true);
            Visual = gameObject.AddComponent<CharacterVisual>();
            RebuildVisual();
        }

        public void RebuildVisual() => Visual.Build(Data.look, Data.classId, Data.ascendancy);

        public void Recalc(bool fill = false)
        {
            float hpFrac = Stats != null && Stats.MaxHp > 0 ? Hp / Stats.MaxHp : 1;
            float mpFrac = Stats != null && Stats.MaxMp > 0 ? Mp / Stats.MaxMp : 1;
            Stats = StatBlock.Compute(Data);
            Hp = fill ? Stats.MaxHp : Mathf.Clamp(hpFrac * Stats.MaxHp, 1, Stats.MaxHp);
            Mp = fill ? Stats.MaxMp : Mathf.Clamp(mpFrac * Stats.MaxMp, 0, Stats.MaxMp);
            OnChanged?.Invoke();
        }

        void Update()
        {
            if (Dead) return;
            Hp = Mathf.Min(Stats.MaxHp, Hp + Stats.Regen * Time.deltaTime);
            Mp = Mathf.Min(Stats.MaxMp, Mp + Stats.MpRegen * Time.deltaTime);
            if (rageTimer > 0) rageTimer -= Time.deltaTime;
            if (shieldTimer > 0) shieldTimer -= Time.deltaTime;
            Data.playSeconds += Time.deltaTime;
        }

        public void TakeDamage(float dmg, Vector3 from)
        {
            if (Dead) return;
            float dr = Stats.DamageReduction + (shieldTimer > 0 ? 0.5f : 0);
            float final = dmg * (1 - Mathf.Clamp(dr, 0, 0.85f));
            Hp -= final;
            HUD.Instance?.DamageNumber(transform.position + Vector3.up * 2.2f, final, false, true);
            Visual?.Flash();
            if (Hp <= 0) { Hp = 0; GameManager.Instance.OnPlayerDied(); }
        }

        public void Heal(float amount)
        {
            if (Dead) return;
            Hp = Mathf.Min(Stats.MaxHp, Hp + amount);
        }

        public void GainXp(long amount)
        {
            Data.xp += amount;
            Data.classXp += amount;
            bool lvl = false, clvl = false;
            while (Data.xp >= CharacterData.XpToNext(Data.level)) { Data.xp -= CharacterData.XpToNext(Data.level); Data.level++; lvl = true; }
            while (Data.classXp >= CharacterData.ClassXpToNext(Data.classLevel)) { Data.classXp -= CharacterData.ClassXpToNext(Data.classLevel); Data.classLevel++; clvl = true; }
            if (lvl)
            {
                Recalc(true);
                FX.Burst(transform.position + Vector3.up, 2.5f, new Color(1f, 0.85f, 0.3f), 0.8f);
                Toast.Show($"Новый уровень: {Data.level}! Очков талантов: {Data.FreeTalentPoints}");
                SaveSystem.Save(Data);
            }
            if (clvl)
            {
                Recalc();
                var cls = ClassDefs.Get(Data.classId);
                string extra = "";
                for (int i = 0; i < cls.skills.Length; i++)
                    if (cls.skillUnlockClassLevel[i] == Data.classLevel) extra = $" Открыто умение «{cls.skills[i].name}»!";
                Toast.Show($"Мастерство класса «{cls.name}»: {Data.classLevel}.{extra}", 3.5f);
            }
            OnChanged?.Invoke();
        }
    }
}
