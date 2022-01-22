using System;
using System.Collections;
using System.Collections.Generic;
using DG.Tweening;
using UnityEngine;

public class CharController : MonoBehaviour
{
    [SerializeField]
    private Animator animationController;

    private Tween currentMove;

    [SerializeField] private float robotSpeed = 1;
    // Start is called before the first frame update
    void Start()
    {
        if (animationController == null)
        {
            animationController = GetComponentInChildren<Animator>();
        }
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
                currentMove?.Kill();

                float distance = Vector3.Distance(transform.position, hit.point);
                currentMove = transform.DOMove(hit.point, distance * robotSpeed).SetEase(Ease.Linear);
                currentMove.OnComplete(OnDestinationReached);
                transform.DOLookAt(hit.point, 0.2f);
                animationController.SetBool("Walking", true);
                animationController.SetBool("Idling", false);
                
            }
        }
    }

    void OnDestinationReached()
    {
        animationController.SetBool("Walking", false);
        animationController.SetBool("Idling", true);
    }
}
