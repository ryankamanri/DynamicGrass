using UnityEngine;


namespace Grass.Script
{
    [ExecuteInEditMode]
    public class GrassCollider : MonoBehaviour
    {
        public float radius = 1;
        public Vector3 centryOffcet = Vector3.zero;

        public Vector3 Position
        {
            get
            {
                return this.transform.position + centryOffcet;
            }
        }

        // Start is called once before the first execution of Update after the MonoBehaviour is created
        void Start()
        {

        }

        // Update is called once per frame
        void Update()
        {
            
        }
        private void OnDrawGizmos()
        {
            Gizmos.color = new Color((float)0xed / 0xff, (float)0x65 / 0xff, 1,1);
            Gizmos.DrawWireSphere(Position, radius);
        }
        

    }
}
