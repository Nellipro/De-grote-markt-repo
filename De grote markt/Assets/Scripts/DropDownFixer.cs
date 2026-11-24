using UnityEngine;

public class DropDownFixer : MonoBehaviour
{
    [Header("Assign Your Weather GameObjects")]
    [SerializeField] private GameObject rainObject;
    [SerializeField] private GameObject snowObject;

    /// <summary>
    /// Connect this to the Dropdown's "On Value Changed (Int32)" under Dynamic int.
    /// 0 = Clear, 1 = Rain, 2 = Snow (adjust order to match your Dropdown options).
    /// </summary>
    public virtual void SetWeatherByChoice(int choiceIndex)
    {
        // 1. Turn off everything first
        if (rainObject != null) rainObject.SetActive(false);
        if (snowObject != null) snowObject.SetActive(false);

        // 2. Turn on only the selected one
        switch (choiceIndex)
        {
            case 0:
                // Clear weather: everything stays off
                break;
            case 1:
                if (rainObject != null) rainObject.SetActive(true);
                break;
            case 2:
                if (snowObject != null) snowObject.SetActive(true);
                break;
        }
    }
}
