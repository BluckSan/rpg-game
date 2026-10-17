using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace RPG
{
    /// <summary>Окно пассивного дерева талантов: перемещение пальцем, зум щипком/колёсиком, выбор узлов, пути превращения.</summary>
    public class TalentTreeUI : MonoBehaviour, IDragHandler, IScrollHandler
    {
        CharacterData data;
        RectTransform viewport, content;
        Text pointsText, infoTitle, infoBody;
        Button learnBtn;
        RectTransform ascList;
        int selectedNode = -1;
        float zoom = 0.7f;
        float lastPinch;
        readonly Dictionary<int, Image> nodeImages = new Dictionary<int, Image>();
        readonly Dictionary<long, Image> lineImages = new Dictionary<long, Image>();
        TalentTree tree;
        bool dirty;

        void Start()
        {
            data = GameManager.Instance.Data;
            tree = TalentTree.Instance;
            var root = (RectTransform)transform;
            var bg = UI.Panel(root, new Color(0.03f, 0.03f, 0.05f, 0.97f), "Bg"); bg.rectTransform.Place(0, 0, 1, 1);

            viewport = UI.Rect("Viewport", root); viewport.Place(0, 0, 0.72f, 1);
            viewport.gameObject.AddComponent<RectMask2D>();
            var vImg = viewport.gameObject.AddComponent<Image>(); vImg.color = new Color(0, 0, 0, 0.01f);
            // события перетаскивания ловит это окно (IDragHandler) — пробрасываем через компонент на viewport
            var fwd = viewport.gameObject.AddComponent<DragForwarder>(); fwd.target = this;

            content = UI.Rect("Content", viewport);
            content.sizeDelta = new Vector2(1600, 1600);
            content.localScale = Vector3.one * zoom;

            BuildTree();

            // правая панель
            var side = UI.Panel(root, UI.PanelColor, "Side"); side.rectTransform.Place(0.72f, 0, 1, 1);
            var title = UI.Label(side.transform, "Дерево талантов", 40, TextAnchor.MiddleCenter, UI.AccentColor); title.rectTransform.Place(0, 0.92f, 1, 0.99f);
            pointsText = UI.Label(side.transform, "", 28, TextAnchor.MiddleCenter); pointsText.rectTransform.Place(0, 0.86f, 1, 0.92f);

            var info = UI.Panel(side.transform, new Color(0, 0, 0, 0.4f), "Info"); info.rectTransform.Place(0.04f, 0.56f, 0.96f, 0.86f);
            infoTitle = UI.Label(info.transform, "Выберите узел", 32, TextAnchor.UpperLeft, UI.AccentColor); infoTitle.rectTransform.Place(0.05f, 0.7f, 0.95f, 0.96f);
            infoBody = UI.Label(info.transform, "Перемещайте дерево пальцем, приближайте двумя пальцами.", 25, TextAnchor.UpperLeft); infoBody.rectTransform.Place(0.05f, 0.25f, 0.95f, 0.72f);
            learnBtn = UI.Button(info.transform, "Изучить", Learn, new Color(0.3f, 0.5f, 0.25f), 30);
            ((RectTransform)learnBtn.transform).Place(0.05f, 0.04f, 0.95f, 0.22f);

            var ascTitle = UI.Label(side.transform, "Пути превращения", 30, TextAnchor.MiddleCenter, UI.AccentColor); ascTitle.rectTransform.Place(0, 0.5f, 1, 0.555f);
            var ascPanel = UI.Rect("AscPanel", side.transform); ascPanel.Place(0.03f, 0.14f, 0.97f, 0.5f);
            ascList = UI.ScrollList(ascPanel, out var sc, 8); ((RectTransform)sc.transform).Place(0, 0, 1, 1);

            var reset = UI.Button(side.transform, "Сброс", ResetTree, new Color(0.45f, 0.18f, 0.15f), 28);
            ((RectTransform)reset.transform).Place(0.04f, 0.02f, 0.36f, 0.12f);
            var close = UI.Button(side.transform, "Закрыть", Close, UI.ButtonColor, 30);
            ((RectTransform)close.transform).Place(0.4f, 0.02f, 0.96f, 0.12f);

            CenterOn(tree.Get(tree.StartNodeFor(data.classId)));
            Refresh();
        }

        void BuildTree()
        {
            // линии
            var drawn = new HashSet<long>();
            foreach (var n in tree.Nodes)
                foreach (var l in n.links)
                {
                    long key = n.id < l ? ((long)n.id << 32) | (uint)l : ((long)l << 32) | (uint)n.id;
                    if (!drawn.Add(key)) continue;
                    var m = tree.Get(l); if (m == null) continue;
                    var a = new Vector2(n.x, n.y); var b = new Vector2(m.x, m.y);
                    var img = UI.Panel(content, new Color(0.3f, 0.3f, 0.35f), "Line"); img.raycastTarget = false;
                    var rt = img.rectTransform;
                    rt.anchoredPosition = (a + b) / 2;
                    rt.sizeDelta = new Vector2((b - a).magnitude, 6);
                    rt.localRotation = Quaternion.Euler(0, 0, Mathf.Atan2(b.y - a.y, b.x - a.x) * Mathf.Rad2Deg);
                    lineImages[key] = img;
                }
            // узлы
            foreach (var n in tree.Nodes)
            {
                float size = n.type == "keystone" ? 78 : n.type == "notable" ? 54 : n.type == "start" ? 64 : 34;
                var ring = UI.Panel(content, Color.black, "Node" + n.id);
                ring.sprite = UI.Circle; ring.type = Image.Type.Simple;
                ring.rectTransform.anchoredPosition = new Vector2(n.x, n.y);
                ring.rectTransform.sizeDelta = Vector2.one * (size + 10);
                var inner = UI.Panel(ring.transform, Color.gray, "Inner"); inner.sprite = UI.Circle; inner.type = Image.Type.Simple; inner.raycastTarget = false;
                inner.rectTransform.Place(0, 0, 1, 1); inner.rectTransform.offsetMin = Vector2.one * 5; inner.rectTransform.offsetMax = -Vector2.one * 5;
                var btn = ring.gameObject.AddComponent<Button>();
                int id = n.id;
                btn.onClick.AddListener(() => Select(id));
                var fwd = ring.gameObject.AddComponent<DragForwarder>(); fwd.target = this;
                nodeImages[n.id] = inner;
                if (n.type == "keystone" || n.type == "start")
                {
                    var lbl = UI.Label(ring.transform, n.type == "start" ? ClassDefs.Get(n.classId).name : n.name, 22, TextAnchor.UpperCenter);
                    lbl.rectTransform.anchoredPosition = new Vector2(0, -size * 0.5f - 30); lbl.rectTransform.sizeDelta = new Vector2(260, 40);
                    lbl.gameObject.AddComponent<Outline>().effectColor = Color.black;
                }
            }
            // подписи регионов
            foreach (var r in tree.data.regions)
            {
                var key = tree.KeystoneOf(r.id); if (key == null) continue;
                var dir = new Vector2(key.x, key.y).normalized;
                var t = UI.Label(content, r.name.ToUpperInvariant(), 34, TextAnchor.MiddleCenter, r.Color * 1.3f);
                t.rectTransform.anchoredPosition = new Vector2(key.x, key.y) * 0.62f + new Vector2(-dir.y, dir.x) * 120; t.rectTransform.sizeDelta = new Vector2(300, 50);
                t.fontStyle = FontStyle.Bold;
                var c = t.color; c.a = 0.55f; t.color = c;
            }
        }

        Color NodeColor(TalentNode n, out Color lineColor)
        {
            var region = tree.Region(n.region);
            Color rc = region != null ? region.Color : new Color(0.85f, 0.8f, 0.65f);
            bool has = data.talents.Contains(n.id);
            lineColor = rc;
            if (has) return Color.Lerp(rc, Color.white, 0.25f);
            if (tree.CanAllocate(data, n.id)) return Color.Lerp(rc, Color.black, 0.35f);
            return new Color(0.18f, 0.18f, 0.2f);
        }

        void Refresh()
        {
            foreach (var n in tree.Nodes)
            {
                var col = NodeColor(n, out _);
                nodeImages[n.id].color = col;
                var ring = nodeImages[n.id].transform.parent.GetComponent<Image>();
                bool has = data.talents.Contains(n.id);
                bool avail = !has && tree.CanAllocate(data, n.id);
                ring.color = n.id == selectedNode ? Color.white : has ? UI.AccentColor : avail ? new Color(0.6f, 0.6f, 0.6f) : new Color(0.1f, 0.1f, 0.12f);
            }
            foreach (var kv in lineImages)
            {
                int a = (int)(kv.Key >> 32), b = (int)(kv.Key & 0xffffffff);
                bool ha = data.talents.Contains(a), hb = data.talents.Contains(b);
                var na = tree.Get(a); var nb = tree.Get(b);
                var reg = tree.Region(!string.IsNullOrEmpty(na.region) ? na.region : nb.region);
                Color rc = reg != null ? reg.Color : new Color(0.85f, 0.75f, 0.5f);
                kv.Value.color = ha && hb ? Color.Lerp(rc, Color.white, 0.3f) : ha || hb ? Color.Lerp(rc, Color.black, 0.5f) : new Color(0.2f, 0.2f, 0.24f);
            }
            pointsText.text = $"Свободных очков: <b>{data.FreeTalentPoints}</b>   (изучено {data.talents.Count - 1})";
            UpdateInfo();
            BuildAscList();
        }

        void UpdateInfo()
        {
            var n = tree.Get(selectedNode);
            if (n == null) { learnBtn.gameObject.SetActive(false); return; }
            var region = tree.Region(n.region);
            string typeName = n.type == "keystone" ? "Ключевой талант" : n.type == "notable" ? "Особый талант" : n.type == "start" ? "Стартовая точка" : "Малый талант";
            infoTitle.text = n.type == "start" ? $"Начало: {ClassDefs.Get(n.classId).name}" : n.name;
            var sb = new System.Text.StringBuilder();
            sb.Append("<i>").Append(typeName).Append(region != null ? " · " + region.name : "").Append("</i>\n");
            foreach (var m in n.mods) sb.Append(StatBlock.Describe(m)).Append('\n');
            if (n.type == "keystone")
            {
                var asc = AscendancyDefs.All.Find(a => a.region == n.region);
                if (asc != null) sb.Append("\nОткрывает путь: <b>").Append(asc.name).Append("</b>");
            }
            infoBody.text = sb.ToString();
            bool has = data.talents.Contains(n.id);
            learnBtn.gameObject.SetActive(!has && n.type != "start");
            learnBtn.interactable = tree.CanAllocate(data, n.id);
            UI.ButtonText(learnBtn).text = data.FreeTalentPoints <= 0 ? "Нет очков" : learnBtn.interactable ? "Изучить" : "Недоступно (нет связи)";
        }

        void BuildAscList()
        {
            UI.Clear(ascList);
            foreach (var a in AscendancyDefs.All)
            {
                var aa = a;
                bool current = data.ascendancy == a.id;
                bool can = AscendancyDefs.CanAscend(data, a, out var reason);
                int pts = tree.PointsInRegion(data, a.region);
                var row = UI.Panel(ascList, current ? a.color * 0.6f + new Color(0, 0, 0, 1) : new Color(0.12f, 0.12f, 0.16f), "Asc");
                row.Height(110);
                var t = UI.Label(row.transform, $"<b>{a.name}</b>  <size=20>({pts} очк.)</size>\n<size=20>{(current ? "Выбран. Умение: " + a.skill.name : can ? "Доступен!" : reason)}</size>", 26, TextAnchor.MiddleLeft);
                t.rectTransform.Place(0.04f, 0, 0.7f, 1);
                var dot = UI.Panel(row.transform, a.color, "Color"); dot.rectTransform.Place(0, 0, 0.02f, 1);
                if (can)
                {
                    var b = UI.Button(row.transform, "Превратиться", () => Ascend(aa), new Color(0.7f, 0.45f, 0.15f), 22);
                    ((RectTransform)b.transform).Place(0.7f, 0.15f, 0.98f, 0.85f);
                }
                else
                {
                    var b = UI.Button(row.transform, "Инфо", () => { infoTitle.text = aa.name; infoBody.text = aa.description + $"\n\nУмение: {aa.skill.name} — {aa.skill.description}\nТребуется: {AscendancyDefs.RequiredLevel} ур., ключевой талант региона и {AscendancyDefs.RequiredRegionPoints} очков в нём."; learnBtn.gameObject.SetActive(false); selectedNode = -1; }, UI.ButtonColor, 22);
                    ((RectTransform)b.transform).Place(0.7f, 0.15f, 0.98f, 0.85f);
                }
            }
        }

        void Ascend(AscendancyDef a)
        {
            data.ascendancy = a.id;
            dirty = true;
            GameManager.Instance.ApplyCharacterChanges(true);
            Toast.Show($"Вы стали: {a.name}! Новое умение: {a.skill.name}", 4f);
            Refresh();
        }

        void Select(int id) { selectedNode = id; Refresh(); }

        void Learn()
        {
            if (tree.Allocate(data, selectedNode)) { dirty = true; GameManager.Instance.ApplyCharacterChanges(false); }
            Refresh();
        }

        void ResetTree()
        {
            bool hadAsc = !string.IsNullOrEmpty(data.ascendancy);
            tree.ResetAll(data);
            dirty = true;
            GameManager.Instance.ApplyCharacterChanges(hadAsc);
            Toast.Show("Таланты сброшены");
            Refresh();
        }

        void Close()
        {
            if (dirty) GameManager.Instance.Save();
            HUD.Instance.CloseWindow();
        }

        void CenterOn(TalentNode n)
        {
            if (n == null) return;
            content.anchoredPosition = -new Vector2(n.x, n.y) * zoom;
        }

        public void OnDrag(PointerEventData e)
        {
            if (Input.touchCount >= 2) return;
            var canvas = GetComponentInParent<Canvas>();
            content.anchoredPosition += e.delta / canvas.scaleFactor;
            ClampContent();
        }

        public void OnScroll(PointerEventData e) => ZoomBy(1 + e.scrollDelta.y * 0.1f);

        void ZoomBy(float k)
        {
            float nz = Mathf.Clamp(zoom * k, 0.3f, 1.8f);
            content.anchoredPosition *= nz / zoom;
            zoom = nz; content.localScale = Vector3.one * zoom;
            ClampContent();
        }

        void ClampContent()
        {
            float lim = 800 * zoom;
            var p = content.anchoredPosition;
            content.anchoredPosition = new Vector2(Mathf.Clamp(p.x, -lim, lim), Mathf.Clamp(p.y, -lim, lim));
        }

        void Update()
        {
            if (Input.touchCount == 2)
            {
                float d = Vector2.Distance(Input.GetTouch(0).position, Input.GetTouch(1).position);
                if (lastPinch > 0) ZoomBy(d / lastPinch);
                lastPinch = d;
            }
            else lastPinch = 0;
        }
    }

    /// <summary>Передаёт перетаскивание/прокрутку от дочерних элементов окну дерева.</summary>
    public class DragForwarder : MonoBehaviour, IDragHandler, IScrollHandler, IBeginDragHandler
    {
        public TalentTreeUI target;
        public void OnBeginDrag(PointerEventData e) { }
        public void OnDrag(PointerEventData e) => target.OnDrag(e);
        public void OnScroll(PointerEventData e) => target.OnScroll(e);
    }
}
