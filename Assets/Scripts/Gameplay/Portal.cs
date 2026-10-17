using UnityEngine;

namespace RPG
{
    /// <summary>Переход в другую зону (например, на глобальную карту).</summary>
    public class Portal : MonoBehaviour
    {
        public string targetZone;
        float cooldown;

        void Update()
        {
            if (cooldown > 0) { cooldown -= Time.deltaTime; return; }
            var pc = PlayerCharacter.Instance;
            if (pc == null) return;
            var d = pc.transform.position - transform.position; d.y = 0;
            if (d.magnitude > 2.5f) return;
            cooldown = 4f;
            var z = ZoneRegistry.Get(targetZone);
            if (z == null) return;
            if (!z.available) { Toast.Show($"Путь в «{z.displayName}» откроется в следующих версиях (от {z.minLevel} ур.)", 3.5f); return; }
            if (pc.Data.level < z.minLevel) { Toast.Show($"Нужен {z.minLevel} уровень", 2.5f); return; }
            GameManager.Instance.Save();
            GameSession.TravelTo(targetZone);
        }
    }
}
