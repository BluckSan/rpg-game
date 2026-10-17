using UnityEngine;

namespace RPG
{
    /// <summary>Перемещение от третьего лица относительно камеры (джойстик или WASD).</summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour
    {
        CharacterController cc;
        PlayerCharacter pc;
        float vy;
        public Vector3 Facing => transform.forward;
        public bool MovementLocked;
        Vector3 dashVel; float dashTime;

        void Awake() { cc = GetComponent<CharacterController>(); pc = GetComponent<PlayerCharacter>(); }

        public void Dash(Vector3 dir, float dist, float time)
        {
            dashVel = dir.normalized * dist / time; dashTime = time;
        }

        public void Teleport(Vector3 pos)
        {
            cc.enabled = false; transform.position = pos; cc.enabled = true;
        }

        public void FaceTowards(Vector3 p)
        {
            var d = p - transform.position; d.y = 0;
            if (d.sqrMagnitude > 0.01f) transform.rotation = Quaternion.LookRotation(d);
        }

        void Update()
        {
            if (pc.Dead) return;
            Vector2 input = HUD.Instance != null && HUD.Instance.Joystick != null ? HUD.Instance.Joystick.Value : Vector2.zero;
#if UNITY_EDITOR || UNITY_STANDALONE
            var kb = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
            if (kb.sqrMagnitude > 0.01f) input = kb.normalized;
#endif
            var cam = Camera.main != null ? Camera.main.transform : transform;
            var fwd = cam.forward; fwd.y = 0; fwd.Normalize();
            var right = cam.right; right.y = 0; right.Normalize();
            var move = (fwd * input.y + right * input.x);
            if (move.sqrMagnitude > 1) move.Normalize();

            Vector3 vel;
            if (dashTime > 0) { dashTime -= Time.deltaTime; vel = dashVel; }
            else
            {
                vel = MovementLocked ? Vector3.zero : move * pc.Stats.MoveSpeed;
                if (move.sqrMagnitude > 0.01f && !MovementLocked)
                    transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(move), Time.deltaTime * 12f);
            }
            vy = cc.isGrounded ? -2f : vy - 20f * Time.deltaTime;
            vel.y = vy;
            cc.Move(vel * Time.deltaTime);
            if (transform.position.y < -10) Teleport(GameManager.Instance.SpawnPoint);
        }
    }
}
