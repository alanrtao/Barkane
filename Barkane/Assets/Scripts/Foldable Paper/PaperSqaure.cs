using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PaperSqaure : MonoBehaviour
{
    [SerializeField] private bool playerOccupied = false; //true if the player is on this square
    public bool PlayerOccupied { get => playerOccupied;}
    // public PaperJoint[] joints = new PaperJoint[4]; //ENWS Joints of this square

    public float paperLength = 2f;
    public float paperThickness = 0.001f;
    [SerializeField] private GameObject topHalf;
    public GameObject TopHalf => topHalf;
    [SerializeField] private GameObject bottomHalf;
    public GameObject BottomHalf => bottomHalf;

    public void SetPlayerOccupied(bool value)
    {
        playerOccupied = value;
    }

    //C: Used to prevent Z-fighting when multiple pieces of paper are back-to-back
    public void ShiftVisuals()
    {

    }

    private void OnValidate()
    {
        Vector3 offset = this.transform.rotation * new Vector3(0, paperThickness / 2, 0);
        topHalf.transform.position = this.transform.position + offset;
        bottomHalf.transform.position = this.transform.position - offset;
    }
}
