using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Плавающий экранный джойстик для левой части экрана.</summary>
    public class VirtualJoystick : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        public Vector2 Value { get; private set; }
        RectTransform area, bg, knob;
        Vector2 defaultPos;
        const float Radius = 110f;

        public static VirtualJoystick Create(Transform parent)
        {
            var a = UI.Rect("JoystickArea", parent); a.Place(0, 0, 0.42f, 0.75f);
            var img = a.gameObject.AddComponent<Image>(); img.color = new Color(0, 0, 0, 0.001f);
            var j = a.gameObject.AddComponent<VirtualJoystick>();
            j.area = a;
            var bgImg = UI.Panel(a, new Color(1, 1, 1, 0.18f), "Bg"); bgImg.sprite = UI.Circle; bgImg.type = Image.Type.Simple; bgImg.raycastTarget = false;
            j.bg = bgImg.rectTransform; j.bg.anchorMin = j.bg.anchorMax = Vector2.zero; j.bg.sizeDelta = Vector2.one * Radius * 2;
            j.defaultPos = new Vector2(260, 240); j.bg.anchoredPosition = j.defaultPos;
            var k = UI.Panel(j.bg, new Color(1, 1, 1, 0.55f), "Knob"); k.sprite = UI.Circle; k.type = Image.Type.Simple; k.raycastTarget = false;
            j.knob = k.rectTransform; j.knob.sizeDelta = Vector2.one * 100; j.knob.anchoredPosition = Vector2.zero;
            return j;
        }

        public void OnPointerDown(PointerEventData e)
        {
            RectTransformUtility.ScreenPointToLocalPointInRectangle(area, e.position, e.pressEventCamera, out var lp);
            bg.anchoredPosition = lp + area.rect.size * area.pivot; // в координатах от левого нижнего угла
            OnDrag(e);
        }

        public void OnDrag(PointerEventData e)
        {
            RectTransformUtility.ScreenPointToLocalPointInRectangle(bg, e.position, e.pressEventCamera, out var lp);
            var v = Vector2.ClampMagnitude(lp, Radius);
            knob.anchoredPosition = v;
            Value = v / Radius;
        }

        public void OnPointerUp(PointerEventData e)
        {
            Value = Vector2.zero; knob.anchoredPosition = Vector2.zero; bg.anchoredPosition = defaultPos;
        }
    }

    /// <summary>Кнопка умения с затемнением перезарядки.</summary>
    public class SkillButton : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
    {
        public System.Action onPress;
        public bool Held { get; private set; }
        Image cdOverlay; Text label, cdText; Image icon;

        public static SkillButton Create(Transform parent, string text, Vector2 pos, float size, Color color)
        {
            var r = UI.Rect("Skill_" + text, parent).Fixed(new Vector2(1, 0), pos, Vector2.one * size);
            var bg = r.gameObject.AddComponent<Image>(); bg.sprite = UI.Circle; bg.color = new Color(0, 0, 0, 0.45f);
            var sb = r.gameObject.AddComponent<SkillButton>();
            sb.icon = UI.Panel(r, color, "Icon"); sb.icon.sprite = UI.Circle; sb.icon.type = Image.Type.Simple; sb.icon.raycastTarget = false;
            sb.icon.rectTransform.Place(0, 0, 1, 1); sb.icon.rectTransform.offsetMin = Vector2.one * 8; sb.icon.rectTransform.offsetMax = -Vector2.one * 8;
            sb.cdOverlay = UI.Panel(r, new Color(0, 0, 0, 0.65f), "Cd"); sb.cdOverlay.sprite = UI.Circle; sb.cdOverlay.raycastTarget = false;
            sb.cdOverlay.type = Image.Type.Filled; sb.cdOverlay.fillMethod = Image.FillMethod.Radial360; sb.cdOverlay.fillClockwise = false; sb.cdOverlay.fillOrigin = 2;
            sb.cdOverlay.rectTransform.Place(0, 0, 1, 1); sb.cdOverlay.fillAmount = 0;
            sb.label = UI.Label(r, text, Mathf.RoundToInt(size * 0.17f), TextAnchor.MiddleCenter);
            sb.label.rectTransform.Place(-0.2f, 0, 1.2f, 1); sb.label.gameObject.AddComponent<Outline>();
            sb.cdText = UI.Label(r, "", Mathf.RoundToInt(size * 0.3f), TextAnchor.MiddleCenter);
            sb.cdText.rectTransform.Place(0, 0, 1, 1);
            return sb;
        }

        public void SetLabel(string s) { label.text = s; }
        public void SetColor(Color c) { icon.color = c; }

        public void SetCooldown(float remaining, float total, string lockedText = null)
        {
            if (lockedText != null) { cdOverlay.fillAmount = 1; cdText.text = lockedText; cdText.fontSize = 22; return; }
            cdText.fontSize = Mathf.RoundToInt(((RectTransform)transform).sizeDelta.x * 0.3f);
            cdOverlay.fillAmount = total > 0 ? Mathf.Clamp01(remaining / total) : 0;
            cdText.text = remaining > 0.05f ? Mathf.CeilToInt(remaining).ToString() : "";
        }

        public void OnPointerDown(PointerEventData e) { Held = true; onPress?.Invoke(); transform.localScale = Vector3.one * 0.92f; }
        public void OnPointerUp(PointerEventData e) { Held = false; transform.localScale = Vector3.one; }
    }
}
