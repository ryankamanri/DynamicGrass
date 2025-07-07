using System.Collections.Generic;
using UnityEngine;

namespace Grass.Script
{
    [ExecuteInEditMode]
    public class GetPlayerPos : MonoBehaviour
    {
        //public GameObject player;
        
        private GrassCollider[] _cols;
        private List<Vector4> _poss = new List<Vector4>();

        public Material material;

        // Start is called before the first frame update
        void Start()
        {
            _cols = GameObject.FindObjectsOfType<GrassCollider>();
        }

        // Update is called once per frame
        void Update()
        {
            _poss.Clear();
            foreach (var col in _cols)
            {
                _poss.Add(new Vector4(col.Position.x,col.Position.y, col.Position.z, col.radius));
            }
            if (_poss != null)
            {
                material.SetVectorArray("_Players",_poss.ToArray());
            }
            else
            {
                print("no player");
            }
        }
    }
}


//LZX completed this script in 2024/05/06
//LZX-TC-VS-2024-05-05-001