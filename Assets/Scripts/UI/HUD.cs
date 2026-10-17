using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Игровой интерфейс: полосы здоровья/маны/опыта, джойстик, кнопки умений, окна.</summary>
    public class HUD : MonoBehaviour
    {
        public static HUD Instance;
        public VirtualJoystick Joystick;
        public bool AttackHeld => attackBtn != null && attackBtn.Held;

        GameManager gm;
        Canvas canvas;
        Image hpFill, mpFill, xpFill;
        Text hpText, mpText, xpText, nameText, potionText, talentBadge, goldText;
        SkillButton attackBtn, potionBtn;
        readonly SkillButton[] skillBtns = new SkillButton[4];
        RectTransform worldLayer, pickupLog, bossBar;
        Image bossFill; Text bossName;
        readonly List<(RectTransform rt, Image fill, Text name)> enemyBars = new List<(RectTransform, Image, Text)>();
        readonly List<(Text t, Vector3 world, float life, Vector2 drift)> numbers = new List<(Text, Vector3, float, Vector2)>();
        GameObject openWindow;
        PlayerCombat combat;

        public void Init(GameManager g)
        {
            Instance = this; gm = g;
            combat = gm.Player.GetComponent<PlayerCombat>();
            canvas = UI.Canvas("HUDCanvas", 10);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;

            worldLayer = UI.Rect("WorldLayer", root); worldLayer.Place(0, 0, 1, 1);
            Joystick = VirtualJoystick.Create(root);

            // портрет и полосы
            var frame = UI.Panel(root, new Color(0, 0, 0, 0.45f), "Status"); frame.rectTransform.Fixed(new Vector2(0, 1), new Vector2(20, -20), new Vector2(560, 170));
            frame.raycastTarget = false;
            nameText = UI.Label(frame.transform, "", 28); nameText.rectTransform.Place(0.03f, 0.72f, 0.97f, 0.98f);
            var hpBar = UI.Bar(frame.transform, new Color(0.8f, 0.15f, 0.15f), out hpFill, out hpText); hpBar.rectTransform.Place(0.03f, 0.4f, 0.97f, 0.68f);
            var mpBar = UI.Bar(frame.transform, new Color(0.2f, 0.4f, 0.9f), out mpFill, out mpText); mpBar.rectTransform.Place(0.03f, 0.08f, 0.97f, 0.36f);
            goldText = UI.Label(root, "", 26, TextAnchor.UpperLeft, new Color(1f, 0.85f, 0.35f));
            goldText.rectTransform.Fixed(new Vector2(0, 1), new Vector2(26, -196), new Vector2(500, 40));

            var xpBar = UI.Bar(root, new Color(0.85f, 0.65f, 0.15f), out xpFill, out xpText); xpBar.rectTransform.Place(0.25f, 0, 0.75f, 0); xpBar.rectTransform.offsetMax = new Vector2(0, 26);
            xpText.fontSize = 18;

            // кнопки окон
            var talents = UI.Button(root, "Таланты", () => Open<TalentTreeUI>(), new Color(0.35f, 0.25f, 0.45f), 28);
            ((RectTransform)talents.transform).Fixed(new Vector2(1, 1), new Vector2(-20, -20), new Vector2(190, 80));
            talentBadge = UI.Label(talents.transform, "", 26, TextAnchor.MiddleCenter, Color.white);
            var badge = UI.Panel(talents.transform, new Color(0.85f, 0.2f, 0.2f), "Badge"); badge.sprite = UI.Circle; badge.type = Image.Type.Simple;
            badge.rectTransform.Fixed(new Vector2(1, 1), new Vector2(14, 14), new Vector2(44, 44));
            talentBadge.transform.SetParent(badge.transform, false); talentBadge.rectTransform.Place(0, 0, 1, 1);
            var hero = UI.Button(root, "Герой", () => Open<InventoryUI>(), UI.ButtonColor, 28);
            ((RectTransform)hero.transform).Fixed(new Vector2(1, 1), new Vector2(-220, -20), new Vector2(170, 80));
            var menu = UI.Button(root, "Меню", () => Open<PauseMenuUI>(), UI.ButtonColor, 28);
            ((RectTransform)menu.transform).Fixed(new Vector2(1, 1), new Vector2(-400, -20), new Vector2(150, 80));

            // боевые кнопки
            var cls = ClassDefs.Get(gm.Data.classId);
            attackBtn = SkillButton.Create(root, cls.skills[0].name, new Vector2(-60, 60), 230, new Color(0.75f, 0.3f, 0.2f));
            Vector2[] pos = { Vector2.zero, new Vector2(-320, 60), new Vector2(-280, 250), new Vector2(-110, 320) };
            for (int i = 1; i < 4; i++)
            {
                int slot = i;
                var s = combat.GetSkill(i);
                skillBtns[i] = SkillButton.Create(root, s != null ? s.name : "Путь", pos[i], 150, s != null ? s.color * 0.8f : Color.gray);
                skillBtns[i].onPress = () => combat.TryUse(slot);
            }
            potionBtn = SkillButton.Create(root, "Зелье", new Vector2(-470, 40), 110, new Color(0.8f, 0.15f, 0.25f));
            potionBtn.onPress = combat.UsePotion;
            potionText = UI.Label(potionBtn.transform, "", 26, TextAnchor.LowerRight); potionText.rectTransform.Place(0, 0, 1, 1);

            pickupLog = UI.Rect("PickupLog", root); pickupLog.Fixed(new Vector2(0, 0.5f), new Vector2(24, 0), new Vector2(520, 300));
            var vl = pickupLog.gameObject.AddComponent<VerticalLayoutGroup>(); vl.childAlignment = TextAnchor.LowerLeft; vl.childControlHeight = false; vl.childForceExpandHeight = false; vl.spacing = 4;

            // полоса босса
            var bb = UI.Bar(root, new Color(0.7f, 0.1f, 0.1f), out bossFill, out bossName);
            bossBar = bb.rectTransform; bossBar.Fixed(new Vector2(0.5f, 1), new Vector2(0, -30), new Vector2(800, 46));
            bossName.fontSize = 26; bb.gameObject.SetActive(false);

            RefreshSkillButtons();
        }

        public void RefreshSkillButtons()
        {
            for (int i = 1; i < 4; i++)
            {
                var s = combat.GetSkill(i);
                skillBtns[i].SetLabel(s != null ? s.name : "Путь");
                skillBtns[i].SetColor(s != null ? s.color * 0.8f + new Color(0, 0, 0, 1) : new Color(0.3f, 0.3f, 0.3f));
            }
        }

        public void Open<T>() where T : Component
        {
            if (openWindow != null) Destroy(openWindow);
            var win = UI.Rect(typeof(T).Name, canvas.transform); win.Place(0, 0, 1, 1);
            openWindow = win.gameObject;
            win.gameObject.AddComponent<T>();
            Time.timeScale = 0f;
        }

        public void CloseWindow()
        {
            if (openWindow != null) Destroy(openWindow);
            openWindow = null;
            Time.timeScale = 1f;
            RefreshSkillButtons();
        }

        void OnDestroy() { Time.timeScale = 1f; }

        public void DamageNumber(Vector3 world, float amount, bool crit, bool toPlayer)
        {
            var t = UI.Label(worldLayer, Mathf.RoundToInt(amount).ToString(), crit ? 46 : 32, TextAnchor.MiddleCenter,
                toPlayer ? new Color(1f, 0.3f, 0.3f) : crit ? new Color(1f, 0.85f, 0.2f) : Color.white);
            t.rectTransform.sizeDelta = new Vector2(200, 60);
            if (crit) t.text += "!";
            t.gameObject.AddComponent<Outline>().effectColor = Color.black;
            numbers.Add((t, world, 0.9f, new Vector2(Random.Range(-40f, 40f), 0)));
        }

        public void Pickup(string text, Color c)
        {
            var t = UI.Label(pickupLog, text, 26, TextAnchor.MiddleLeft, c);
            t.rectTransform.sizeDelta = new Vector2(520, 34);
            t.gameObject.AddComponent<Outline>().effectColor = Color.black;
            Destroy(t.gameObject, 3f);
        }

        void Update()
        {
            var p = gm.Player; var d = gm.Data;
            if (p == null || p.Stats == null) return;
            var asc = AscendancyDefs.Get(d.ascendancy);
            nameText.text = $"<b>{d.name}</b>  ур. {d.level}  ·  {(asc != null ? asc.name : ClassDefs.Get(d.classId).name)} (мастерство {d.classLevel})";
            hpFill.fillAmount = p.Hp / p.Stats.MaxHp; hpText.text = $"{Mathf.CeilToInt(p.Hp)} / {Mathf.RoundToInt(p.Stats.MaxHp)}";
            mpFill.fillAmount = p.Mp / p.Stats.MaxMp; mpText.text = $"{Mathf.FloorToInt(p.Mp)} / {Mathf.RoundToInt(p.Stats.MaxMp)}";
            long need = CharacterData.XpToNext(d.level);
            xpFill.fillAmount = (float)d.xp / need; xpText.text = $"Опыт {d.xp} / {need}";
            goldText.text = $"Золото: {d.gold}";
            potionText.text = "x" + d.potions + " ";
            int free = d.FreeTalentPoints;
            talentBadge.transform.parent.gameObject.SetActive(free > 0);
            talentBadge.text = free.ToString();

            attackBtn.SetCooldown(0, 0);
            for (int i = 1; i < 4; i++)
            {
                if (!combat.IsUnlocked(i, out var reason)) skillBtns[i].SetCooldown(0, 0, reason);
                else skillBtns[i].SetCooldown(combat.cooldowns[i], combat.MaxCooldown(i));
            }

            UpdateNumbers();
            UpdateEnemyBars();
        }

        void UpdateNumbers()
        {
            var cam = Camera.main;
            for (int i = numbers.Count - 1; i >= 0; i--)
            {
                var n = numbers[i];
                n.life -= Time.unscaledDeltaTime;
                if (n.life <= 0 || cam == null) { Destroy(n.t.gameObject); numbers.RemoveAt(i); continue; }
                var sp = cam.WorldToScreenPoint(n.world);
                if (sp.z < 0) { n.t.enabled = false; }
                else
                {
                    n.t.enabled = true;
                    RectTransformUtility.ScreenPointToLocalPointInRectangle(worldLayer, sp, null, out var lp);
                    n.t.rectTransform.anchoredPosition = lp + n.drift + new Vector2(0, (0.9f - n.life) * 120f);
                    var c = n.t.color; c.a = Mathf.Clamp01(n.life * 2); n.t.color = c;
                }
                numbers[i] = n;
            }
        }

        void UpdateEnemyBars()
        {
            var cam = Camera.main; if (cam == null) return;
            int used = 0;
            Enemy boss = null;
            var ppos = gm.Player.transform.position;
            foreach (var e in Enemy.All)
            {
                if (!e.Alive) continue;
                if (e.def.boss && Vector3.Distance(e.transform.position, ppos) < 30) boss = e;
                if (Vector3.Distance(e.transform.position, ppos) > 22) continue;
                var sp = cam.WorldToScreenPoint(e.transform.position + Vector3.up * (e.def.boss ? 5.2f : 2.4f));
                if (sp.z < 0) continue;
                if (used >= enemyBars.Count)
                {
                    var bg = UI.Panel(worldLayer, new Color(0, 0, 0, 0.6f), "EBar"); bg.raycastTarget = false;
                    bg.rectTransform.sizeDelta = new Vector2(120, 14);
                    var f = UI.Panel(bg.transform, new Color(0.85f, 0.2f, 0.15f), "Fill"); f.type = Image.Type.Filled; f.fillMethod = Image.FillMethod.Horizontal; f.raycastTarget = false;
                    f.rectTransform.Place(0, 0, 1, 1); f.rectTransform.offsetMin = Vector2.one * 2; f.rectTransform.offsetMax = -Vector2.one * 2;
                    var nm = UI.Label(bg.transform, "", 20, TextAnchor.LowerCenter); nm.rectTransform.Place(-1, 1, 2, 3.5f);
                    nm.gameObject.AddComponent<Outline>().effectColor = Color.black;
                    enemyBars.Add((bg.rectTransform, f, nm));
                }
                var bar = enemyBars[used++];
                bar.rt.gameObject.SetActive(true);
                RectTransformUtility.ScreenPointToLocalPointInRectangle(worldLayer, sp, null, out var lp);
                bar.rt.anchoredPosition = lp;
                bar.fill.fillAmount = e.hp / e.maxHp;
                bar.name.text = e.DisplayName;
                int diff = e.level - gm.Data.level;
                bar.name.color = diff >= 3 ? new Color(1f, 0.35f, 0.3f) : diff <= -3 ? new Color(0.7f, 0.7f, 0.7f) : Color.white;
            }
            for (int i = used; i < enemyBars.Count; i++) enemyBars[i].rt.gameObject.SetActive(false);
            bossBar.gameObject.SetActive(boss != null);
            if (boss != null) { bossFill.fillAmount = boss.hp / boss.maxHp; bossName.text = boss.DisplayName; }
        }
    }
}
