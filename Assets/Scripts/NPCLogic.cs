using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class NPCLogic : MonoBehaviour
{
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    private void OnMouseDown()
    {
        FocusCharacter();
    }

    private void OnMouseEnter()
    {
        CharacterHover();
    }

    private void CharacterHover()
    {
        Debug.Log("Character Hover:" + name);
    }

    private void FocusCharacter()
    {
        Debug.Log("Character Focused");
    }
}
