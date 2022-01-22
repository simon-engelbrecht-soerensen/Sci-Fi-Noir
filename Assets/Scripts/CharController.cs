using System;
using System.Collections;
using System.Collections.Generic;
using DG.Tweening;
using UnityEngine;

public class CharController : MonoBehaviour
{
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetMouseButtonDown(0))
        {
            MouseClick();
        }
    }

    private void MouseClick()
    {
        Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
        RaycastHit hit;
        Debug.Log("Raycast cast");

        if (Physics.Raycast(ray, out hit))
        {
            Debug.Log("Raycast cast");
            if (hit.collider.CompareTag("Floor"))
            {
                Debug.Log("Move Character To:" + hit.point);
                transform.DOMove(hit.point, 2);
                transform.DOLookAt(hit.point, 0.2f);
            }
        }
    }
}
