using UnityEngine;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Окно героя: характеристики, снаряжение и инвентарь.</summary>
    public class InventoryUI : MonoBehaviour
    {
        CharacterData data;
        Text statsText, detailTitle, detailBody;
        RectTransform equipRoot, invContent;
        Button actionBtn, sellBtn;
        ItemData selected; bool selectedEquipped;

        void Start()
        {
            data = GameManager.Instance.Data;
            var root = (RectTransform)transform;
            var bg = UI.Panel(root, new Color(0.03f, 0.03f, 0.05f, 0.96f), "Bg"); bg.rectTransform.Place(0, 0, 1, 1);
            var title = UI.Label(root, "Герой", 48, TextAnchor.MiddleLeft, UI.AccentColor); title.rectTransform.Place(0.03f, 0.9f, 0.5f, 0.98f);

            // характеристики
            var sp = UI.Panel(root, UI.PanelColor, "Stats"); sp.rectTransform.Place(0.02f, 0.04f, 0.3f, 0.89f);
            statsText = UI.Label(sp.transform, "", 25, TextAnchor.UpperLeft); statsText.rectTransform.Place(0, 0, 1, 1);
            statsText.rectTransform.offsetMin = new Vector2(20, 16); statsText.rectTransform.offsetMax = new Vector2(-20, -16);

            // снаряжение
            var ep = UI.Panel(root, UI.PanelColor, "Equip"); ep.rectTransform.Place(0.31f, 0.47f, 0.62f, 0.89f);
            var et = UI.Label(ep.transform, "Снаряжение", 30, TextAnchor.UpperCenter, UI.AccentColor); et.rectTransform.Place(0, 0.85f, 1, 0.98f);
            equipRoot = UI.Rect("Slots", ep.transform); equipRoot.Place(0.03f, 0.03f, 0.97f, 0.84f);
            var grid = equipRoot.gameObject.AddComponent<GridLayoutGroup>(); grid.cellSize = new Vector2(270, 150); grid.spacing = new Vector2(12, 12); grid.childAlignment = TextAnchor.MiddleCenter;

            // детали
            var dp = UI.Panel(root, UI.PanelColor, "Detail"); dp.rectTransform.Place(0.31f, 0.04f, 0.62f, 0.46f);
            detailTitle = UI.Label(dp.transform, "Выберите предмет", 30, TextAnchor.UpperLeft, UI.AccentColor); detailTitle.rectTransform.Place(0.04f, 0.78f, 0.96f, 0.96f);
            detailBody = UI.Label(dp.transform, "", 24, TextAnchor.UpperLeft); detailBody.rectTransform.Place(0.04f, 0.28f, 0.96f, 0.78f);
            actionBtn = UI.Button(dp.transform, "Надеть", OnAction, new Color(0.3f, 0.5f, 0.25f), 28); ((RectTransform)actionBtn.transform).Place(0.04f, 0.04f, 0.6f, 0.24f);
            sellBtn = UI.Button(dp.transform, "Продать", OnSell, new Color(0.5f, 0.35f, 0.1f), 28); ((RectTransform)sellBtn.transform).Place(0.63f, 0.04f, 0.96f, 0.24f);

            // инвентарь
            var ip = UI.Panel(root, UI.PanelColor, "Inventory"); ip.rectTransform.Place(0.63f, 0.14f, 0.98f, 0.89f);
            invContent = UI.ScrollList(ip.transform, out var sc, 6); ((RectTransform)sc.transform).Place(0, 0, 1, 1);

            var close = UI.Button(root, "Закрыть", () => { GameManager.Instance.Save(); HUD.Instance.CloseWindow(); }, UI.ButtonColor, 32);
            ((RectTransform)close.transform).Place(0.63f, 0.03f, 0.98f, 0.12f);
            Refresh();
        }

        void Refresh()
        {
            var st = GameManager.Instance.Player.Stats;
            var cls = ClassDefs.Get(data.classId);
            var asc = AscendancyDefs.Get(data.ascendancy);
            statsText.text =
                $"<size=34><b>{data.name}</b></size>\n" +
                $"{cls.name}{(asc != null ? " → " + asc.name : "")}\n" +
                $"Уровень {data.level} · мастерство {data.classLevel}\n" +
                $"Опыт класса: {data.classXp}/{CharacterData.ClassXpToNext(data.classLevel)}\n\n" +
                $"Здоровье: {Mathf.RoundToInt(st.MaxHp)}\n" +
                $"Мана: {Mathf.RoundToInt(st.MaxMp)}\n" +
                $"Урон: {Mathf.RoundToInt(st.Damage * st.DamageMult * (cls.spellBased ? st.SpellMult : 1))}\n" +
                $"Скорость атаки: {st.AttackSpeed * 100:0}%\n" +
                $"Шанс крита: {st.Crit * 100:0.#}% (x{st.CritMult:0.##})\n" +
                $"Броня: {Mathf.RoundToInt(st.Armor)} (-{st.DamageReduction * 100:0}% урона)\n" +
                $"Регенерация: {st.Regen:0.#}/с · мана {st.MpRegen:0.#}/с\n" +
                $"Похищение жизни: {st.Leech * 100:0.#}%\n" +
                $"Скорость бега: {st.MoveSpeed:0.#}\n" +
                $"Сокр. перезарядки: {st.Cdr * 100:0}%\n\n" +
                $"Золото: {data.gold} · Зелья: {data.potions}\n" +
                $"Убито врагов: {data.kills}";

            UI.Clear(equipRoot);
            for (int s = 0; s < 4; s++)
            {
                var it = data.GetEquipped((ItemSlot)s);
                var label = $"<size=20>{LootGenerator.SlotNames[s]}</size>\n" + (it != null ? $"<color=#{ColorUtility.ToHtmlStringRGB(LootGenerator.RarityColors[it.rarity])}>{it.name}</color>" : "<color=#666>пусто</color>");
                var item = it;
                var b = UI.Button(equipRoot, label, () => { if (item != null) Select(item, true); }, new Color(0.15f, 0.16f, 0.2f), 24);
            }

            UI.Clear(invContent);
            var header = UI.Label(invContent, $"Инвентарь ({data.inventory.Count}/{GameManager.InventorySize})", 28, TextAnchor.MiddleCenter, UI.AccentColor); header.Height(50);
            foreach (var it in data.inventory)
            {
                var item = it;
                var b = UI.Button(invContent, $"<color=#{ColorUtility.ToHtmlStringRGB(LootGenerator.RarityColors[it.rarity])}>{it.name}</color>  <size=20>({LootGenerator.SlotNames[it.slot]}, ур. {it.itemLevel})</size>",
                    () => Select(item, false), item == selected ? new Color(0.35f, 0.3f, 0.15f) : new Color(0.15f, 0.16f, 0.2f), 26);
                UI.ButtonText(b).alignment = TextAnchor.MiddleLeft;
                b.Height(70);
            }
            UpdateDetail();
        }

        void Select(ItemData it, bool equipped) { selected = it; selectedEquipped = equipped; Refresh(); }

        int SellPrice(ItemData it) => 5 + it.itemLevel * 3 * (it.rarity + 1);

        void UpdateDetail()
        {
            bool has = selected != null;
            actionBtn.gameObject.SetActive(has); sellBtn.gameObject.SetActive(has && !selectedEquipped);
            if (!has) { detailTitle.text = "Выберите предмет"; detailBody.text = "Нажмите на предмет в инвентаре или снаряжении."; return; }
            detailTitle.text = selected.name; detailTitle.color = LootGenerator.RarityColors[selected.rarity];
            var body = LootGenerator.Describe(selected);
            if (!selectedEquipped)
            {
                var cur = data.GetEquipped(selected.Slot);
                if (cur != null) body += $"\n\n<size=20><color=#999>Сейчас: {cur.name} ({(cur.Slot == ItemSlot.Weapon ? "урон" : "броня")} {cur.baseValue})</color></size>";
            }
            detailBody.text = body;
            UI.ButtonText(actionBtn).text = selectedEquipped ? "Снять" : "Надеть";
            UI.ButtonText(sellBtn).text = $"Продать ({SellPrice(selected)})";
        }

        void OnAction()
        {
            if (selected == null) return;
            if (selectedEquipped)
            {
                if (selected.Slot == ItemSlot.Weapon) { Toast.Show("Без оружия никак!"); return; }
                if (data.inventory.Count >= GameManager.InventorySize) { Toast.Show("Инвентарь полон"); return; }
                data.equipped.Remove(selected); data.inventory.Add(selected);
            }
            else
            {
                var cur = data.GetEquipped(selected.Slot);
                if (cur != null) { data.equipped.Remove(cur); data.inventory.Add(cur); }
                data.inventory.Remove(selected); data.equipped.Add(selected);
            }
            selected = null;
            GameManager.Instance.ApplyCharacterChanges(false);
            Refresh();
        }

        void OnSell()
        {
            if (selected == null || selectedEquipped) return;
            data.gold += SellPrice(selected);
            data.inventory.Remove(selected);
            selected = null;
            Refresh();
        }
    }

    /// <summary>Меню паузы.</summary>
    public class PauseMenuUI : MonoBehaviour
    {
        void Start()
        {
            var root = (RectTransform)transform;
            var bg = UI.Panel(root, new Color(0, 0, 0, 0.75f), "Bg"); bg.rectTransform.Place(0, 0, 1, 1);
            var p = UI.Panel(root, UI.PanelColor, "Panel"); p.rectTransform.Fixed(new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(700, 760));
            var t = UI.Label(p.transform, "Пауза", 54, TextAnchor.MiddleCenter, UI.AccentColor); t.rectTransform.Place(0, 0.85f, 1, 0.97f);
            float y = 0.68f;
            void Btn(string name, UnityEngine.Events.UnityAction a, Color? c = null)
            {
                var b = UI.Button(p.transform, name, a, c ?? UI.ButtonColor, 34);
                ((RectTransform)b.transform).Place(0.1f, y, 0.9f, y + 0.13f); y -= 0.16f;
            }
            Btn("Продолжить", () => HUD.Instance.CloseWindow(), new Color(0.3f, 0.5f, 0.25f));
            Btn("Сохранить", () => { GameManager.Instance.Save(); Toast.Show("Игра сохранена"); });
            bool shadows = QualitySettings.shadows != ShadowQuality.Disable;
            Btn(shadows ? "Тени: вкл" : "Тени: выкл", null);
            var shadowBtn = p.transform.GetChild(p.transform.childCount - 1).GetComponent<Button>();
            shadowBtn.onClick.AddListener(() =>
            {
                bool on = QualitySettings.shadows == ShadowQuality.Disable;
                QualitySettings.shadows = on ? ShadowQuality.All : ShadowQuality.Disable;
                PlayerPrefs.SetInt("shadows", on ? 1 : 0);
                UI.ButtonText(shadowBtn).text = on ? "Тени: вкл" : "Тени: выкл";
            });
            Btn("В главное меню", () => { Time.timeScale = 1; GameSession.ToMenu(); }, new Color(0.45f, 0.18f, 0.15f));
        }
    }
}
