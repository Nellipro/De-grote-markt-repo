using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.XR;
using UnityEngine.XR.OpenXR.Features.Meta;

public class VrFpsUnlocker : MonoBehaviour
{
    [Header("Target Refresh Rate")]
    [Tooltip("Common VR rates: 72, 80, 90, 120")]
    [SerializeField] private float targetRefreshRate = 90f;

    protected virtual void Start()
    {
        SetRefreshRate(targetRefreshRate);
    }

    public virtual void SetRefreshRate(float desiredRate)
    {
        List<XRDisplaySubsystem> displaySubsystems = new List<XRDisplaySubsystem>();
        SubsystemManager.GetSubsystems(displaySubsystems);

        foreach (var subsystem in displaySubsystems)
        {
            if (!subsystem.running) continue;

            // Allocator.Temp is required and automatically cleans up after the frame
            if (subsystem.TryGetSupportedDisplayRefreshRates(Allocator.Temp, out var supportedRates))
            {
                float bestMatch = 0f;
                foreach (float rate in supportedRates)
                {
                    if (Mathf.Approximately(rate, desiredRate))
                    {
                        bestMatch = rate;
                        break;
                    }
                }

                if (bestMatch > 0f)
                {
                    if (subsystem.TryRequestDisplayRefreshRate(bestMatch))
                    {
                        Debug.Log($"Requested VR refresh rate: {bestMatch} Hz");
                    }
                    else
                    {
                        Debug.LogWarning($"Failed to request VR refresh rate: {bestMatch} Hz");
                    }
                }
                else
                {
                    Debug.LogWarning($"Refresh rate {desiredRate} Hz not supported by headset.");
                }
            }
        }
    }
}