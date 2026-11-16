using UnityEngine;
using TMPro;

public class VrFrameRateDisplay : MonoBehaviour
{
    [Header("UI Reference")]
    [SerializeField] private TextMeshProUGUI fpsText;

    [Header("Settings")]
    [Tooltip("How often (in seconds) the text updates so numbers remain readable.")]
    [SerializeField] private float updateInterval = 0.5f;

    private float _accumulatedTime;
    private int _frameCount;
    private float _timeLeft;

    protected virtual void Start()
    {
        _timeLeft = updateInterval;
    }

    protected virtual void Update()
    {
        // Use unscaledDeltaTime so slow-motion or pause states don't skew the reading
        _timeLeft -= Time.unscaledDeltaTime;
        _accumulatedTime += Time.unscaledDeltaTime;
        _frameCount++;

        if (_timeLeft <= 0.0f)
        {
            UpdateDisplay();
            ResetCounters();
        }
    }

    protected virtual void UpdateDisplay()
    {
        if (fpsText == null) return;

        float fps = _frameCount / _accumulatedTime;
        fpsText.text = $"FPS: {Mathf.RoundToInt(fps)}";

        // Optional color feedback for VR comfort thresholds
        if (fps >= 90f)
            fpsText.color = Color.green;
        else if (fps >= 72f)
            fpsText.color = Color.yellow;
        else
            fpsText.color = Color.red;
    }

    private void ResetCounters()
    {
        _timeLeft = updateInterval;
        _accumulatedTime = 0f;
        _frameCount = 0;
    }
}
