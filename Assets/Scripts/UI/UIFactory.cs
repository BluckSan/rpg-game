using System;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Создание интерфейса кодом (uGUI), чтобы проект не зависел от префабов.</summary>
    public static class UI
    {
        static Font font;
        public static Font Font
        {
            get
            {
                if (font == null)
                {
                    font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                    if (font == null) font = Font.CreateDynamicFontFromOSFont(new[] { "Roboto", "Noto Sans", "Arial" }, 32);
                }
                return font;
            }
        }

        static Sprite white;
        public static Sprite White
        {
            get
            {
                if (white == null)
                {
                    var t = new Texture2D(4, 4); var px = new Color[16];
                    for (int i = 0; i < 16; i++) px[i] = Color.white; t.SetPixels(px); t.Apply();
                    white = Sprite.Create(t, new Rect(0, 0, 4, 4), new Vector2(0.5f, 0.5f), 100, 0, SpriteMeshType.FullRect, new Vector4(1, 1, 1, 1));
                }
                return white;
            }
        }

        static Sprite circle;
        public static Sprite Circle
        {
            get
            {
                if (circle == null)
                {
                    int n = 128; var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
                    var px = new Color[n * n]; float r = n / 2f;
                    for (int y = 0; y < n; y++) for (int x = 0; x < n; x++)
                    {
                        float d = Mathf.Sqrt((x - r + 0.5f) * (x - r + 0.5f) + (y - r + 0.5f) * (y - r + 0.5f));
                        px[y * n + x] = new Color(1, 1, 1, Mathf.Clamp01(r - d));
                    }
                    t.SetPixels(px); t.Apply();
                    circle = Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
                }
                return circle;
            }
        }

        public static readonly Color PanelColor = new Color(0.07f, 0.08f, 0.11f, 0.92f);
        public static readonly Color ButtonColor = new Color(0.22f, 0.25f, 0.33f, 1f);
        public static readonly Color AccentColor = new Color(0.85f, 0.6f, 0.2f, 1f);
        public static readonly Color TextColor = new Color(0.95f, 0.93f, 0.88f);

        public static Canvas Canvas(string name, int order = 0)
        {
            EnsureEventSystem();
            var go = new GameObject(name, typeof(RectTransform));
            var c = go.AddComponent<Canvas>();
            c.renderMode = RenderMode.ScreenSpaceOverlay;
            c.sortingOrder = order;
            var s = go.AddComponent<CanvasScaler>();
            s.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            s.referenceResolution = new Vector2(1920, 1080);
            s.matchWidthOrHeight = 0.6f;
            go.AddComponent<GraphicRaycaster>();
            return c;
        }

        public static void EnsureEventSystem()
        {
            if (EventSystem.current != null || UnityEngine.Object.FindAnyObjectByType<EventSystem>() != null) return;
            var es = new GameObject("EventSystem", typeof(EventSystem), typeof(StandaloneInputModule));
            UnityEngine.Object.DontDestroyOnLoad(es);
        }

        public static RectTransform Rect(string name, Transform parent)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            return (RectTransform)go.transform;
        }

        /// <summary>Якоря в долях экрана родителя (0..1).</summary>
        public static RectTransform Place(this RectTransform r, float xMin, float yMin, float xMax, float yMax)
        {
            r.anchorMin = new Vector2(xMin, yMin); r.anchorMax = new Vector2(xMax, yMax);
            r.offsetMin = r.offsetMax = Vector2.zero;
            return r;
        }

        /// <summary>Фиксированный размер от точки привязки.</summary>
        public static RectTransform Fixed(this RectTransform r, Vector2 anchor, Vector2 pos, Vector2 size)
        {
            r.anchorMin = r.anchorMax = anchor; r.pivot = anchor;
            r.anchoredPosition = pos; r.sizeDelta = size;
            return r;
        }

        public static Image Panel(Transform parent, Color c, string name = "Panel")
        {
            var r = Rect(name, parent);
            var img = r.gameObject.AddComponent<Image>();
            img.sprite = White; img.type = Image.Type.Sliced; img.color = c;
            return img;
        }

        public static Text Label(Transform parent, string text, int size = 32, TextAnchor align = TextAnchor.MiddleLeft, Color? color = null)
        {
            var r = Rect("Text", parent);
            var t = r.gameObject.AddComponent<Text>();
            t.font = Font; t.text = text; t.fontSize = size; t.alignment = align;
            t.color = color ?? TextColor; t.raycastTarget = false;
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Overflow;
            t.supportRichText = true;
            return t;
        }

        public static Button Button(Transform parent, string text, UnityAction onClick, Color? color = null, int size = 32)
        {
            var img = Panel(parent, color ?? ButtonColor, "Button_" + text);
            var b = img.gameObject.AddComponent<Button>();
            var cb = b.colors; cb.highlightedColor = new Color(1.1f, 1.1f, 1.1f); cb.pressedColor = new Color(0.7f, 0.7f, 0.7f); b.colors = cb;
            if (onClick != null) b.onClick.AddListener(onClick);
            var t = Label(img.transform, text, size, TextAnchor.MiddleCenter);
            t.rectTransform.Place(0, 0, 1, 1);
            t.rectTransform.offsetMin = new Vector2(8, 4); t.rectTransform.offsetMax = new Vector2(-8, -4);
            return b;
        }

        public static Text ButtonText(Button b) => b.GetComponentInChildren<Text>();

        public static Slider Slider(Transform parent, float min, float max, float value, UnityAction<float> onChange)
        {
            var root = Rect("Slider", parent);
            var s = root.gameObject.AddComponent<Slider>();
            var bg = Panel(root, new Color(0.15f, 0.15f, 0.2f), "Bg"); bg.rectTransform.Place(0, 0.35f, 1, 0.65f);
            var fillArea = Rect("FillArea", root); fillArea.Place(0, 0.35f, 1, 0.65f);
            var fill = Panel(fillArea, AccentColor, "Fill"); fill.rectTransform.Place(0, 0, 1, 1);
            var handleArea = Rect("HandleArea", root); handleArea.Place(0, 0, 1, 1); handleArea.offsetMin = new Vector2(20, 0); handleArea.offsetMax = new Vector2(-20, 0);
            var handle = Panel(handleArea, Color.white, "Handle"); handle.sprite = Circle; handle.type = Image.Type.Simple;
            handle.rectTransform.sizeDelta = new Vector2(44, 0); handle.rectTransform.anchorMin = new Vector2(0, 0); handle.rectTransform.anchorMax = new Vector2(0, 1);
            s.fillRect = fill.rectTransform; s.handleRect = handle.rectTransform; s.targetGraphic = handle;
            s.minValue = min; s.maxValue = max; s.value = value;
            if (onChange != null) s.onValueChanged.AddListener(onChange);
            return s;
        }

        public static InputField Input(Transform parent, string value, string placeholder, UnityAction<string> onChange)
        {
            var img = Panel(parent, new Color(0.12f, 0.13f, 0.17f), "Input");
            var f = img.gameObject.AddComponent<InputField>();
            var t = Label(img.transform, "", 34); t.rectTransform.Place(0, 0, 1, 1); t.rectTransform.offsetMin = new Vector2(16, 4); t.rectTransform.offsetMax = new Vector2(-16, -4);
            t.supportRichText = false; t.raycastTarget = false;
            var ph = Label(img.transform, placeholder, 34, TextAnchor.MiddleLeft, new Color(1, 1, 1, 0.35f)); ph.rectTransform.Place(0, 0, 1, 1); ph.rectTransform.offsetMin = new Vector2(16, 4); ph.rectTransform.offsetMax = new Vector2(-16, -4);
            ph.fontStyle = FontStyle.Italic;
            f.textComponent = t; f.placeholder = ph; f.characterLimit = 16; f.lineType = InputField.LineType.SingleLine;
            f.text = value;
            if (onChange != null) f.onValueChanged.AddListener(onChange);
            return f;
        }

        public static Image Bar(Transform parent, Color fill, out Image fillImage, out Text label)
        {
            var bg = Panel(parent, new Color(0, 0, 0, 0.65f), "Bar");
            fillImage = Panel(bg.transform, fill, "Fill");
            fillImage.type = Image.Type.Filled; fillImage.fillMethod = Image.FillMethod.Horizontal; fillImage.fillOrigin = 0;
            fillImage.rectTransform.Place(0, 0, 1, 1); fillImage.rectTransform.offsetMin = new Vector2(3, 3); fillImage.rectTransform.offsetMax = new Vector2(-3, -3);
            label = Label(bg.transform, "", 24, TextAnchor.MiddleCenter);
            label.rectTransform.Place(0, 0, 1, 1);
            var sh = label.gameObject.AddComponent<Shadow>(); sh.effectDistance = new Vector2(2, -2);
            return bg;
        }

        public static void Clear(Transform t)
        {
            for (int i = t.childCount - 1; i >= 0; i--) UnityEngine.Object.Destroy(t.GetChild(i).gameObject);
        }

        /// <summary>Вертикальный список с прокруткой. Возвращает content.</summary>
        public static RectTransform ScrollList(Transform parent, out ScrollRect scroll, float spacing = 10)
        {
            var root = Rect("Scroll", parent);
            scroll = root.gameObject.AddComponent<ScrollRect>();
            var vp = Rect("Viewport", root); vp.Place(0, 0, 1, 1);
            vp.gameObject.AddComponent<RectMask2D>();
            var img = vp.gameObject.AddComponent<Image>(); img.color = new Color(0, 0, 0, 0.01f);
            var content = Rect("Content", vp);
            content.anchorMin = new Vector2(0, 1); content.anchorMax = new Vector2(1, 1); content.pivot = new Vector2(0.5f, 1);
            content.offsetMin = content.offsetMax = Vector2.zero;
            var lg = content.gameObject.AddComponent<VerticalLayoutGroup>();
            lg.spacing = spacing; lg.childControlHeight = true; lg.childControlWidth = true; lg.childForceExpandHeight = false; lg.childForceExpandWidth = true;
            lg.padding = new RectOffset(6, 6, 6, 6);
            var fit = content.gameObject.AddComponent<ContentSizeFitter>(); fit.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.viewport = vp; scroll.content = content; scroll.horizontal = false; scroll.vertical = true;
            scroll.movementType = ScrollRect.MovementType.Clamped; scroll.scrollSensitivity = 30;
            return content;
        }

        public static LayoutElement Height(this Component c, float h)
        {
            var le = c.gameObject.GetComponent<LayoutElement>();
            if (le == null) le = c.gameObject.AddComponent<LayoutElement>();
            le.preferredHeight = h; le.minHeight = h;
            return le;
        }
    }

    /// <summary>Всплывающие сообщения внизу экрана.</summary>
    public class Toast : MonoBehaviour
    {
        static Toast inst;
        Text text; CanvasGroup group; float t;

        public static void Show(string msg, float seconds = 2.5f)
        {
            if (inst == null)
            {
                var c = UI.Canvas("Toast", 100);
                DontDestroyOnLoad(c.gameObject);
                inst = c.gameObject.AddComponent<Toast>();
                var p = UI.Panel(c.transform, new Color(0, 0, 0, 0.75f));
                p.rectTransform.Fixed(new Vector2(0.5f, 0.78f), Vector2.zero, new Vector2(1100, 90));
                p.raycastTarget = false;
                inst.group = p.gameObject.AddComponent<CanvasGroup>(); inst.group.blocksRaycasts = false;
                inst.text = UI.Label(p.transform, "", 32, TextAnchor.MiddleCenter);
                inst.text.rectTransform.Place(0, 0, 1, 1);
            }
            inst.text.text = msg; inst.t = seconds; inst.group.alpha = 1;
        }

        void Update()
        {
            if (t > 0) { t -= Time.unscaledDeltaTime; group.alpha = Mathf.Clamp01(t * 2); }
        }
    }
}
