using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    public class ClassDef
    {
        public string id, name, description;
        public Color color;
        public float baseHp, hpPerLevel, baseMp, mpPerLevel, baseDamage, damagePerLevel;
        public float attackRange, attackInterval;
        public bool ranged, spellBased;
        public string weaponName;
        public SkillDef[] skills; // [0] = базовая атака, [1], [2] = умения класса
        public int[] skillUnlockClassLevel; // уровень класса для открытия умений
    }

    public enum SkillKind { MeleeSwing, Projectile, Spin, Dash, Volley, Fireball, FrostNova, ArrowRain, Rage, HolyShield, ShadowStrike, Meteor, Summon, BeastRoar }

    public class SkillDef
    {
        public string id, name, description;
        public SkillKind kind;
        public float damageMult = 1f, cooldown, manaCost, radius = 3f, range = 10f;
        public Color color = Color.white;
    }

    public static class ClassDefs
    {
        public static readonly List<ClassDef> All = new List<ClassDef>
        {
            new ClassDef
            {
                id = "warrior", name = "Воин", weaponName = "Ржавый меч",
                description = "Мастер ближнего боя. Много здоровья и брони.\nПути развития: Берсерк, Паладин, Друид.",
                color = new Color(0.85f, 0.3f, 0.2f),
                baseHp = 140, hpPerLevel = 14, baseMp = 40, mpPerLevel = 3, baseDamage = 12, damagePerLevel = 2.2f,
                attackRange = 2.6f, attackInterval = 0.75f,
                skills = new[]
                {
                    new SkillDef { id = "w_attack", name = "Удар", kind = SkillKind.MeleeSwing, radius = 2.6f, color = Color.white },
                    new SkillDef { id = "w_spin", name = "Вихрь", description = "Круговой удар по всем врагам рядом", kind = SkillKind.Spin, damageMult = 1.6f, cooldown = 6, manaCost = 15, radius = 4.2f, color = new Color(1f,0.6f,0.3f) },
                    new SkillDef { id = "w_dash", name = "Рывок", description = "Рывок вперёд, ранит врагов на пути", kind = SkillKind.Dash, damageMult = 2.2f, cooldown = 8, manaCost = 15, radius = 2f, range = 8, color = new Color(1f,0.85f,0.4f) },
                },
                skillUnlockClassLevel = new[] { 1, 1, 3 }
            },
            new ClassDef
            {
                id = "archer", name = "Лучник", weaponName = "Кривой лук",
                description = "Стреляет издалека, быстрый и ловкий. Высокий шанс крита.\nПути развития: Тень, Друид, Берсерк.",
                color = new Color(0.3f, 0.7f, 0.3f),
                baseHp = 100, hpPerLevel = 10, baseMp = 60, mpPerLevel = 4, baseDamage = 10, damagePerLevel = 2f,
                attackRange = 14f, attackInterval = 0.6f, ranged = true,
                skills = new[]
                {
                    new SkillDef { id = "a_attack", name = "Выстрел", kind = SkillKind.Projectile, range = 16, color = new Color(0.9f,0.8f,0.5f) },
                    new SkillDef { id = "a_volley", name = "Залп", description = "Веер из пяти стрел", kind = SkillKind.Volley, damageMult = 0.9f, cooldown = 5, manaCost = 14, range = 16, color = new Color(0.6f,1f,0.6f) },
                    new SkillDef { id = "a_rain", name = "Град стрел", description = "Дождь стрел по области у цели", kind = SkillKind.ArrowRain, damageMult = 2.4f, cooldown = 9, manaCost = 22, radius = 4.5f, range = 14, color = new Color(0.8f,1f,0.4f) },
                },
                skillUnlockClassLevel = new[] { 1, 1, 3 }
            },
            new ClassDef
            {
                id = "mage", name = "Маг", weaponName = "Посох ученика",
                description = "Повелевает стихиями и тьмой. Мощные заклинания, мало здоровья.\nПути развития: Стихийник, Некромант, Паладин.",
                color = new Color(0.3f, 0.45f, 0.95f),
                baseHp = 85, hpPerLevel = 8, baseMp = 120, mpPerLevel = 8, baseDamage = 11, damagePerLevel = 2.4f,
                attackRange = 13f, attackInterval = 0.8f, ranged = true, spellBased = true,
                skills = new[]
                {
                    new SkillDef { id = "m_bolt", name = "Искра", kind = SkillKind.Projectile, range = 15, color = new Color(0.5f,0.7f,1f) },
                    new SkillDef { id = "m_fireball", name = "Огненный шар", description = "Взрывается и поджигает область", kind = SkillKind.Fireball, damageMult = 2.6f, cooldown = 5, manaCost = 20, radius = 3.2f, range = 15, color = new Color(1f,0.45f,0.1f) },
                    new SkillDef { id = "m_nova", name = "Ледяная нова", description = "Замораживает и ранит врагов вокруг", kind = SkillKind.FrostNova, damageMult = 1.5f, cooldown = 8, manaCost = 25, radius = 5f, color = new Color(0.6f,0.9f,1f) },
                },
                skillUnlockClassLevel = new[] { 1, 1, 3 }
            },
        };

        public static ClassDef Get(string id) => All.Find(c => c.id == id) ?? All[0];
    }
}
