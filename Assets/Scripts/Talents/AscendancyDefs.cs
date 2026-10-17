using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Пути превращения (ascendancy). Открываются через регион дерева талантов.</summary>
    public class AscendancyDef
    {
        public string id, name, region, description;
        public Color color;
        public List<StatMod> mods;
        public SkillDef skill;
    }

    public static class AscendancyDefs
    {
        public const int RequiredLevel = 8;
        public const int RequiredRegionPoints = 6;

        public static readonly List<AscendancyDef> All = new List<AscendancyDef>
        {
            new AscendancyDef { id = "berserker", region = "berserker", name = "Берсерк", color = new Color(0.9f,0.2f,0.1f),
                description = "Багровая ярость: тело растёт, глаза горят.\n+25% урона, +10% скорости атаки.",
                mods = new List<StatMod>{ new StatMod("dmg%",25), new StatMod("as%",10) },
                skill = new SkillDef { id="asc_rage", name="Ярость", description="8 сек: +50% урона и скорости атаки", kind=SkillKind.Rage, cooldown=20, manaCost=20, color=new Color(1f,0.2f,0.1f) } },
            new AscendancyDef { id = "paladin", region = "paladin", name = "Паладин", color = new Color(1f,0.85f,0.3f),
                description = "Золотые латы и нимб света.\n+30% брони, +15% здоровья.",
                mods = new List<StatMod>{ new StatMod("armor%",30), new StatMod("hp%",15) },
                skill = new SkillDef { id="asc_shield", name="Священный щит", description="Лечит 35% здоровья и снижает урон на 6 сек", kind=SkillKind.HolyShield, cooldown=22, manaCost=25, color=new Color(1f,0.9f,0.4f) } },
            new AscendancyDef { id = "elementalist", region = "elementalist", name = "Стихийник", color = new Color(0.3f,0.7f,1f),
                description = "Вокруг кружат сферы огня, льда и молний.\n+30% урона чар, +10% сокращения перезарядки.",
                mods = new List<StatMod>{ new StatMod("spell%",30), new StatMod("cdr%",10), new StatMod("dmg%",10) },
                skill = new SkillDef { id="asc_meteor", name="Метеор", description="Огромный метеор по области", kind=SkillKind.Meteor, damageMult=5f, cooldown=16, manaCost=40, radius=6f, range=15, color=new Color(1f,0.4f,0.1f) } },
            new AscendancyDef { id = "necromancer", region = "necromancer", name = "Некромант", color = new Color(0.55f,0.3f,0.8f),
                description = "Бледная кожа, тёмная аура, парящие черепа.\n+20% урона чар, +3% похищения жизни.",
                mods = new List<StatMod>{ new StatMod("spell%",20), new StatMod("leech%",3), new StatMod("dmg%",10) },
                skill = new SkillDef { id="asc_summon", name="Поднять скелетов", description="Призывает 2 скелетов на 25 сек", kind=SkillKind.Summon, damageMult=0.6f, cooldown=25, manaCost=35, color=new Color(0.7f,0.5f,1f) } },
            new AscendancyDef { id = "shadow", region = "shadow", name = "Тень", color = new Color(0.25f,0.2f,0.35f),
                description = "Тело окутано дымом, движения бесшумны.\n+10% крита, +50% силы крита, +10% скорости.",
                mods = new List<StatMod>{ new StatMod("crit",10), new StatMod("critdmg%",50), new StatMod("ms%",10) },
                skill = new SkillDef { id="asc_strike", name="Теневой удар", description="Телепорт к врагу и гарантированный крит", kind=SkillKind.ShadowStrike, damageMult=4f, cooldown=10, manaCost=20, range=14, color=new Color(0.5f,0.3f,0.7f) } },
            new AscendancyDef { id = "druid", region = "druid", name = "Друид-зверь", color = new Color(0.35f,0.6f,0.25f),
                description = "Облик медведя: огромное звериное тело.\n+30% здоровья, +15% урона, +3 регенерации.",
                mods = new List<StatMod>{ new StatMod("hp%",30), new StatMod("dmg%",15), new StatMod("regen",3) },
                skill = new SkillDef { id="asc_roar", name="Рёв зверя", description="Оглушает врагов вокруг и лечит", kind=SkillKind.BeastRoar, damageMult=2f, cooldown=14, manaCost=20, radius=6f, color=new Color(0.5f,0.9f,0.3f) } },
        };

        public static AscendancyDef Get(string id) => string.IsNullOrEmpty(id) ? null : All.Find(a => a.id == id);

        /// <summary>Можно ли выбрать путь. reason — почему нельзя.</summary>
        public static bool CanAscend(CharacterData c, AscendancyDef a, out string reason)
        {
            var tree = TalentTree.Instance;
            if (!string.IsNullOrEmpty(c.ascendancy)) { reason = "Путь уже выбран (сброс талантов отменит его)"; return false; }
            if (c.level < RequiredLevel) { reason = $"Нужен {RequiredLevel} уровень"; return false; }
            var key = tree.KeystoneOf(a.region);
            if (key == null || !c.talents.Contains(key.id)) { reason = $"Изучите ключевой талант «{key?.name}»"; return false; }
            int pts = tree.PointsInRegion(c, a.region);
            if (pts < RequiredRegionPoints) { reason = $"Нужно {RequiredRegionPoints} очков в регионе ({pts})"; return false; }
            reason = ""; return true;
        }
    }
}
