using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Создание персонажа в стиле MMORPG: пол, телосложение, лицо, причёска, цвета, имя, класс.</summary>
    public class CharacterCreatorUI : MonoBehaviour
    {
        PreviewStage stage;
        Action<CharacterData> done;
        Appearance look = new Appearance();
        string charName = "";
        string classId = "warrior";
        RectTransform content;
        Text classDesc;
        InputField nameField;
        readonly List<Action> refreshers = new List<Action>();

        static readonly string[] maleNames = { "Арвид", "Торин", "Ратибор", "Кайрон", "Эльдар", "Ярослав", "Гримм", "Святогор" };
        static readonly string[] femaleNames = { "Лиара", "Мирослава", "Айрин", "Велена", "Сэлин", "Злата", "Иветта", "Рагна" };

        public void Init(PreviewStage s, Action<CharacterData> onDone)
        {
            stage = s; done = onDone;
            stage.SetOffset(1.0f);
            var root = (RectTransform)transform;

            var title = UI.Label(root, "Создание персонажа", 54, TextAnchor.MiddleLeft, UI.AccentColor);
            title.rectTransform.Place(0.03f, 0.9f, 0.6f, 0.98f); title.fontStyle = FontStyle.Bold;

            var panel = UI.Panel(root, UI.PanelColor); panel.rectTransform.Place(0.02f, 0.14f, 0.45f, 0.89f);
            content = UI.ScrollList(panel.transform, out var sc, 14);
            ((RectTransform)sc.transform).Place(0, 0, 1, 1);

            // вращение превью
            var drag = UI.Rect("DragArea", root); drag.Place(0.47f, 0.3f, 1f, 0.9f);
            drag.gameObject.AddComponent<Image>().color = new Color(0, 0, 0, 0.001f);
            drag.gameObject.AddComponent<DragRotateArea>().stage = stage;

            var descPanel = UI.Panel(root, new Color(0, 0, 0, 0.55f)); descPanel.rectTransform.Place(0.62f, 0.14f, 0.98f, 0.32f);
            classDesc = UI.Label(descPanel.transform, "", 26, TextAnchor.UpperLeft);
            classDesc.rectTransform.Place(0, 0, 1, 1); classDesc.rectTransform.offsetMin = new Vector2(18, 12); classDesc.rectTransform.offsetMax = new Vector2(-18, -12);

            var back = UI.Button(root, "Назад", () => done(null), UI.ButtonColor, 32);
            ((RectTransform)back.transform).Place(0.02f, 0.03f, 0.14f, 0.12f);
            var rnd = UI.Button(root, "Случайно", Randomize, UI.ButtonColor, 32);
            ((RectTransform)rnd.transform).Place(0.15f, 0.03f, 0.3f, 0.12f);
            var create = UI.Button(root, "СОЗДАТЬ", Create, new Color(0.75f, 0.5f, 0.15f), 40);
            ((RectTransform)create.transform).Place(0.74f, 0.03f, 0.98f, 0.12f);

            BuildOptions();
            Randomize();
        }

        void BuildOptions()
        {
            Section("Имя");
            nameField = UI.Input(content, charName, "Введите имя героя", v => charName = v);
            nameField.Height(80);

            Section("Класс");
            var classRow = Row(100);
            foreach (var c in ClassDefs.All)
            {
                var cid = c.id; var cdef = c;
                var b = UI.Button(classRow, c.name, () => { classId = cid; Refresh(); }, UI.ButtonColor, 32);
                refreshers.Add(() => b.GetComponent<Image>().color = classId == cid ? cdef.color * 0.8f + new Color(0, 0, 0, 1) : UI.ButtonColor);
            }

            Section("Пол");
            var gRow = Row(80);
            string[] g = { "Мужской", "Женский" };
            for (int i = 0; i < 2; i++)
            {
                int gi = i;
                var b = UI.Button(gRow, g[i], () => { look.gender = gi; if (gi == 1 && look.face == 2) look.face = 0; Refresh(); }, UI.ButtonColor, 30);
                refreshers.Add(() => b.GetComponent<Image>().color = look.gender == gi ? new Color(0.45f, 0.35f, 0.15f) : UI.ButtonColor);
            }

            SliderRow("Рост", 0.85f, 1.15f, () => look.height, v => look.height = v);
            SliderRow("Телосложение", 0.8f, 1.25f, () => look.build, v => look.build = v);
            Swatches("Цвет кожи", CharacterVisual.SkinColors, () => look.skin, i => look.skin = i);
            Cycler("Лицо", CharacterVisual.FaceNames, () => look.face, i => look.face = i);
            Cycler("Причёска", CharacterVisual.HairStyleNames, () => look.hairStyle, i => look.hairStyle = i);
            Swatches("Цвет волос", CharacterVisual.HairColors, () => look.hairColor, i => look.hairColor = i);
            Swatches("Цвет глаз", CharacterVisual.EyeColors, () => look.eyeColor, i => look.eyeColor = i);
        }

        void Section(string name)
        {
            var t = UI.Label(content, name, 30, TextAnchor.LowerLeft, UI.AccentColor);
            t.Height(46);
        }

        RectTransform Row(float h)
        {
            var r = UI.Rect("Row", content);
            var lg = r.gameObject.AddComponent<HorizontalLayoutGroup>();
            lg.spacing = 10; lg.childControlWidth = true; lg.childControlHeight = true; lg.childForceExpandWidth = true; lg.childForceExpandHeight = true;
            r.Height(h);
            return r;
        }

        void SliderRow(string name, float min, float max, Func<float> get, Action<float> set)
        {
            Section(name);
            var row = Row(60);
            var s = UI.Slider(row, min, max, get(), v => { set(v); RebuildPreview(); });
            refreshers.Add(() => s.SetValueWithoutNotify(get()));
        }

        void Swatches(string name, Color[] colors, Func<int> get, Action<int> set)
        {
            Section(name);
            var row = Row(70);
            for (int i = 0; i < colors.Length; i++)
            {
                int ii = i;
                var img = UI.Panel(row, colors[i], "Swatch");
                var b = img.gameObject.AddComponent<Button>();
                b.onClick.AddListener(() => { set(ii); Refresh(); });
                var frame = UI.Panel(img.transform, new Color(1, 1, 1, 0), "Frame"); frame.rectTransform.Place(0, 0, 1, 1);
                var ol = frame.gameObject.AddComponent<Outline>(); ol.effectDistance = new Vector2(4, 4); frame.raycastTarget = false;
                refreshers.Add(() => { ol.effectColor = get() == ii ? UI.AccentColor : new Color(0, 0, 0, 0); frame.color = new Color(1, 1, 1, get() == ii ? 0.01f : 0f); });
            }
        }

        void Cycler(string name, string[] options, Func<int> get, Action<int> set)
        {
            Section(name);
            var row = Row(70);
            Text label = null;
            UI.Button(row, "<", () => { set((get() - 1 + options.Length) % options.Length); Refresh(); }, UI.ButtonColor, 34);
            var mid = UI.Panel(row, new Color(0.12f, 0.13f, 0.17f), "Value");
            label = UI.Label(mid.transform, "", 30, TextAnchor.MiddleCenter); label.rectTransform.Place(0, 0, 1, 1);
            mid.gameObject.AddComponent<LayoutElement>().flexibleWidth = 3;
            UI.Button(row, ">", () => { set((get() + 1) % options.Length); Refresh(); }, UI.ButtonColor, 34);
            refreshers.Add(() => label.text = options[get()]);
        }

        void Refresh()
        {
            foreach (var r in refreshers) r();
            var cls = ClassDefs.Get(classId);
            classDesc.text = $"<b>{cls.name}</b>\n{cls.description}";
            RebuildPreview();
        }

        void RebuildPreview() { stage.Show(look, classId); }

        void Randomize()
        {
            look.gender = UnityEngine.Random.Range(0, 2);
            look.height = UnityEngine.Random.Range(0.92f, 1.08f);
            look.build = UnityEngine.Random.Range(0.9f, 1.12f);
            look.skin = UnityEngine.Random.Range(0, 6);
            look.face = look.gender == 1 ? UnityEngine.Random.Range(0, 2) : UnityEngine.Random.Range(0, 4);
            look.hairStyle = look.gender == 1 ? (UnityEngine.Random.value < 0.5f ? 2 : 3) : UnityEngine.Random.Range(0, 6);
            look.hairColor = UnityEngine.Random.Range(0, CharacterVisual.HairColors.Length);
            look.eyeColor = UnityEngine.Random.Range(0, CharacterVisual.EyeColors.Length);
            var pool = look.gender == 1 ? femaleNames : maleNames;
            charName = pool[UnityEngine.Random.Range(0, pool.Length)];
            nameField.SetTextWithoutNotify(charName);
            Refresh();
        }

        void Create()
        {
            var n = (charName ?? "").Trim();
            if (n.Length < 2) { Toast.Show("Имя должно быть не короче 2 букв"); return; }
            foreach (var other in SaveSystem.LoadAll())
                if (string.Equals(other.name, n, StringComparison.OrdinalIgnoreCase)) { Toast.Show("Персонаж с таким именем уже есть"); return; }
            var c = CharacterFactory.CreateDefault(n, classId);
            c.look = look;
            Toast.Show($"Персонаж {n} создан!");
            done(c);
        }
    }
}
