using UnityEngine;
using UnityEngine.EventSystems;

namespace RPG
{
    /// <summary>Камера от третьего лица: свайп по правой части экрана — поворот, два пальца — зум.</summary>
    public class ThirdPersonCamera : MonoBehaviour
    {
        public Transform target;
        public float yaw = 0, pitch = 38, distance = 11;
        const float MinDist = 5, MaxDist = 18;
        int rotateFinger = -1; Vector2 lastPos;
        float lastPinch;

        void LateUpdate()
        {
            if (target == null) return;
            HandleInput();
            var rot = Quaternion.Euler(pitch, yaw, 0);
            var focus = target.position + Vector3.up * 1.4f;
            var desired = focus - rot * Vector3.forward * distance;
            // не уходить под землю и сквозь препятствия
            if (Physics.SphereCast(focus, 0.3f, (desired - focus).normalized, out var hit, distance, ~0, QueryTriggerInteraction.Ignore)
                && hit.collider.transform != target && !hit.collider.transform.IsChildOf(target))
                desired = focus + (desired - focus).normalized * Mathf.Max(2f, hit.distance - 0.2f);
            desired.y = Mathf.Max(desired.y, 0.5f);
            transform.position = Vector3.Lerp(transform.position, desired, Time.deltaTime * 14f);
            transform.rotation = Quaternion.LookRotation(focus - transform.position);
        }

        void HandleInput()
        {
            // сенсорный ввод
            int freeTouches = 0; Vector2 a = Vector2.zero, b = Vector2.zero;
            for (int i = 0; i < Input.touchCount; i++)
            {
                var t = Input.GetTouch(i);
                bool overUI = EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(t.fingerId);
                if (t.phase == TouchPhase.Began && !overUI && t.position.x > Screen.width * 0.35f && rotateFinger < 0)
                { rotateFinger = t.fingerId; lastPos = t.position; }
                if (t.fingerId == rotateFinger)
                {
                    if (t.phase == TouchPhase.Moved)
                    {
                        var d = t.position - lastPos; lastPos = t.position;
                        float k = 180f / Screen.height;
                        yaw += d.x * k; pitch = Mathf.Clamp(pitch - d.y * k * 0.6f, 10, 70);
                    }
                    if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled) rotateFinger = -1;
                }
                if (!overUI) { if (freeTouches == 0) a = t.position; else b = t.position; freeTouches++; }
            }
            if (freeTouches == 2)
            {
                float d = Vector2.Distance(a, b);
                if (lastPinch > 0) distance = Mathf.Clamp(distance - (d - lastPinch) * 0.02f, MinDist, MaxDist);
                lastPinch = d;
            }
            else lastPinch = 0;
            if (Input.touchCount == 0) rotateFinger = -1;

#if UNITY_EDITOR || UNITY_STANDALONE
            if (Input.GetMouseButton(1)) { yaw += Input.GetAxis("Mouse X") * 4f; pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * 3f, 10, 70); }
            distance = Mathf.Clamp(distance - Input.mouseScrollDelta.y, MinDist, MaxDist);
#endif
        }
    }
}
