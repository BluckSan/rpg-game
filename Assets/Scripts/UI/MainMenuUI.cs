using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Главное меню: список персонажей (слоты), выбор, удаление, создание.</summary>
    public class MainMenuUI : MonoBehaviour
    {
        Canvas canvas;
        RectTransform listContent, screenRoot;
        Text infoText;
        Button playBtn, deleteBtn;
        List<CharacterData> chars;
        CharacterData selected;
        PreviewStage stage;
        bool confirmDelete;

        void Start()
        {
            stage = PreviewStage.Create();
            canvas = UI.Canvas("MenuCanvas");
            ShowSelect();
        }

        void ShowSelect()
        {
            if (screenRoot) Destroy(screenRoot.gameObject);
            screenRoot = UI.Rect("SelectScreen", canvas.transform); screenRoot.Place(0, 0, 1, 1);
            stage.SetOffset(1.1f);

            var title = UI.Label(screenRoot, "ОСКОЛКИ ЭФИРА", 72, TextAnchor.MiddleLeft, UI.AccentColor);
            title.rectTransform.Place(0.03f, 0.86f, 0.6f, 0.98f); title.fontStyle = FontStyle.Bold;
            title.gameObject.AddComponent<Shadow>().effectDistance = new Vector2(3, -3);
            var sub = UI.Label(screenRoot, "Выбор персонажа", 34); sub.rectTransform.Place(0.03f, 0.8f, 0.5f, 0.87f);

            var listPanel = UI.Panel(screenRoot, UI.PanelColor); listPanel.rectTransform.Place(0.03f, 0.16f, 0.36f, 0.79f);
            listContent = UI.ScrollList(listPanel.transform, out var sc, 12);
            ((RectTransform)sc.transform).Place(0, 0, 1, 1);

            var create = UI.Button(screenRoot, "+ Создать персонажа", () => OpenCreator(), new Color(0.25f, 0.45f, 0.25f), 36);
            ((RectTransform)create.transform).Place(0.03f, 0.04f, 0.36f, 0.14f);

            var infoPanel = UI.Panel(screenRoot, new Color(0, 0, 0, 0.55f)); infoPanel.rectTransform.Place(0.66f, 0.2f, 0.97f, 0.62f);
            infoText = UI.Label(infoPanel.transform, "", 32, TextAnchor.UpperLeft); infoText.rectTransform.Place(0, 0, 1, 1);
            infoText.rectTransform.offsetMin = new Vector2(24, 20); infoText.rectTransform.offsetMax = new Vector2(-24, -20);

            playBtn = UI.Button(screenRoot, "ИГРАТЬ", () => { if (selected != null) GameSession.Play(selected); }, new Color(0.75f, 0.5f, 0.15f), 44);
            ((RectTransform)playBtn.transform).Place(0.66f, 0.04f, 0.88f, 0.16f);
            deleteBtn = UI.Button(screenRoot, "Удалить", OnDelete, new Color(0.45f, 0.15f, 0.15f), 28);
            ((RectTransform)deleteBtn.transform).Place(0.89f, 0.04f, 0.97f, 0.16f);

            var ver = UI.Label(screenRoot, "v" + Application.version + " · офлайн", 22, TextAnchor.LowerRight, new Color(1, 1, 1, 0.4f));
            ver.rectTransform.Place(0.6f, 0.92f, 0.98f, 0.99f);

            RefreshList();
        }

        void RefreshList()
        {
            chars = SaveSystem.LoadAll();
            UI.Clear(listContent);
            if (selected != null) selected = chars.Find(c => c.id == selected.id);
            if (selected == null && chars.Count > 0) selected = chars[chars.Count - 1];
            foreach (var c in chars)
            {
                var cc = c;
                var cls = ClassDefs.Get(c.classId);
                var asc = AscendancyDefs.Get(c.ascendancy);
                string line = $"<b>{c.name}</b>\n<size=24>{(asc != null ? asc.name : cls.name)} · ур. {c.level} · класс {c.classLevel}</size>";
                var b = UI.Button(listContent, line, () => { selected = cc; confirmDelete = false; UpdateSelection(); }, c == selected ? new Color(0.45f, 0.35f, 0.15f) : UI.ButtonColor, 32);
                UI.ButtonText(b).alignment = TextAnchor.MiddleLeft;
                b.Height(120);
            }
            for (int i = chars.Count; i < SaveSystem.MaxSlots; i++)
            {
                var b = UI.Button(listContent, "<color=#888>Пустой слот</color>", () => OpenCreator(), new Color(0.13f, 0.14f, 0.18f), 28);
                b.Height(90);
            }
            UpdateSelection();
        }

        void UpdateSelection()
        {
            // перекрасить кнопки
            int idx = 0;
            foreach (Transform t in listContent)
            {
                if (idx < chars.Count) t.GetComponent<Image>().color = chars[idx] == selected ? new Color(0.45f, 0.35f, 0.15f) : UI.ButtonColor;
                idx++;
            }
            playBtn.interactable = selected != null;
            deleteBtn.interactable = selected != null;
            UI.ButtonText(deleteBtn).text = confirmDelete ? "Точно?" : "Удалить";
            if (selected == null)
            {
                infoText.text = "Нет персонажей.\nСоздайте своего первого героя!";
                stage.Show(null);
                return;
            }
            var c = selected;
            var cls = ClassDefs.Get(c.classId);
            var asc = AscendancyDefs.Get(c.ascendancy);
            var zone = ZoneRegistry.Get(c.zoneId);
            int hrs = (int)(c.playSeconds / 3600), mins = (int)(c.playSeconds / 60) % 60;
            infoText.text = $"<size=44><b>{c.name}</b></size>\n" +
                            $"Класс: {cls.name} (мастерство {c.classLevel})\n" +
                            $"Путь: {(asc != null ? asc.name : "не выбран")}\n" +
                            $"Уровень: {c.level}\n" +
                            $"Локация: {zone?.displayName}\n" +
                            $"Убито врагов: {c.kills}\n" +
                            $"В игре: {hrs} ч {mins} мин";
            stage.Show(c);
        }

        void OnDelete()
        {
            if (selected == null) return;
            if (!confirmDelete) { confirmDelete = true; UpdateSelection(); return; }
            SaveSystem.Delete(selected.id);
            selected = null; confirmDelete = false;
            RefreshList();
        }

        void OpenCreator()
        {
            if (SaveSystem.LoadAll().Count >= SaveSystem.MaxSlots) { Toast.Show("Все слоты заняты. Удалите персонажа."); return; }
            if (screenRoot) Destroy(screenRoot.gameObject);
            screenRoot = UI.Rect("CreatorScreen", canvas.transform); screenRoot.Place(0, 0, 1, 1);
            var cr = screenRoot.gameObject.AddComponent<CharacterCreatorUI>();
            cr.Init(stage, created =>
            {
                if (created != null) { SaveSystem.Save(created); selected = created; }
                ShowSelect();
            });
        }
    }

    /// <summary>3D-сцена предпросмотра персонажа (камера, свет, подиум).</summary>
    public class PreviewStage : MonoBehaviour
    {
        Camera cam; Transform pivot; CharacterVisual visual;
        float yaw = 180, autoSpin = 1;
        float offset;

        public static PreviewStage Create()
        {
            var go = new GameObject("PreviewStage");
            var s = go.AddComponent<PreviewStage>();
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.45f, 0.45f, 0.55f);
            RenderSettings.ambientEquatorColor = new Color(0.3f, 0.28f, 0.3f);
            RenderSettings.ambientGroundColor = new Color(0.15f, 0.12f, 0.1f);
            RenderSettings.fog = false;

            var camGo = new GameObject("MenuCamera"); camGo.tag = "MainCamera";
            s.cam = camGo.AddComponent<Camera>();
            s.cam.clearFlags = CameraClearFlags.SolidColor; s.cam.backgroundColor = new Color(0.08f, 0.07f, 0.1f);
            s.cam.fieldOfView = 35; s.cam.transform.position = new Vector3(0, 1.3f, 5.6f); s.cam.transform.LookAt(new Vector3(0, 1.0f, 0));
            var lightGo = new GameObject("KeyLight"); var l = lightGo.AddComponent<Light>(); l.type = LightType.Directional; l.intensity = 1.1f;
            l.color = new Color(1f, 0.92f, 0.82f); l.shadows = LightShadows.Soft; lightGo.transform.rotation = Quaternion.Euler(35, 150, 0);
            var rim = new GameObject("RimLight").AddComponent<Light>(); rim.type = LightType.Point; rim.range = 8; rim.intensity = 2.5f;
            rim.color = new Color(1f, 0.55f, 0.2f); rim.transform.position = new Vector3(-1.5f, 2.5f, -1.5f);

            s.pivot = new GameObject("Pivot").transform;
            Mat.Prim(PrimitiveType.Cylinder, s.pivot, new Vector3(0, -0.05f, 0), new Vector3(2.2f, 0.05f, 2.2f), new Color(0.2f, 0.18f, 0.2f));
            Mat.Prim(PrimitiveType.Cylinder, s.pivot, new Vector3(0, -0.02f, 0), new Vector3(1.9f, 0.05f, 1.9f), new Color(0.6f, 0.4f, 0.15f), false, 0.6f, 0.3f);
            var vgo = new GameObject("Character"); vgo.transform.SetParent(s.pivot, false);
            s.visual = vgo.AddComponent<CharacterVisual>(); s.visual.speedOverride = 0;
            return s;
        }

        public void SetOffset(float x) { offset = x; }

        public void Show(CharacterData c)
        {
            visual.gameObject.SetActive(c != null);
            if (c != null) visual.Build(c.look, c.classId, c.ascendancy);
        }

        public void Show(Appearance a, string classId)
        {
            visual.gameObject.SetActive(true);
            visual.Build(a, classId, "");
        }

        public void Rotate(float dx) { yaw -= dx * 0.4f; autoSpin = 0; }

        void Update()
        {
            pivot.position = Vector3.Lerp(pivot.position, new Vector3(offset, 0, 0), Time.deltaTime * 6);
            autoSpin = Mathf.MoveTowards(autoSpin, 1, Time.deltaTime * 0.3f);
            yaw += Time.deltaTime * 12 * autoSpin;
            pivot.rotation = Quaternion.Euler(0, yaw, 0);
        }
    }

    /// <summary>Прозрачная область для вращения превью пальцем.</summary>
    public class DragRotateArea : MonoBehaviour, IDragHandler
    {
        public PreviewStage stage;
        public void OnDrag(PointerEventData e) { stage.Rotate(e.delta.x); }
    }
}
