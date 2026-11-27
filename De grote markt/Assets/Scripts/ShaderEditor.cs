using UnityEngine;
using UnityEngine.UI;

public class WeatherShaderUIController : MonoBehaviour
{
    [Header("Target Renderers")]
    [Tooltip("All floor/tile renderers using Custom/VR_Reflective_Tile_Water.")]
    [SerializeField] private Renderer[] targetRenderers;

    [Tooltip("If true, edits the shared material asset directly (changes persist after Play Mode).")]
    [SerializeField] private bool modifySharedMaterial = false;

    [Header("UI Sliders (0 to 1)")]
    [SerializeField] private Slider waterAmountSlider;
    [SerializeField] private Slider snowAmountSlider;

    private static readonly int WaterAmountID = Shader.PropertyToID("_WaterAmount");
    private static readonly int SnowAmountID = Shader.PropertyToID("_SnowAmount");

    protected virtual void OnEnable()
    {
        InitializeSliders();

        if (waterAmountSlider != null)
            waterAmountSlider.onValueChanged.AddListener(SetWaterAmount);

        if (snowAmountSlider != null)
            snowAmountSlider.onValueChanged.AddListener(SetSnowAmount);
    }

    protected virtual void OnDisable()
    {
        if (waterAmountSlider != null)
            waterAmountSlider.onValueChanged.RemoveListener(SetWaterAmount);

        if (snowAmountSlider != null)
            snowAmountSlider.onValueChanged.RemoveListener(SetSnowAmount);
    }

    protected virtual void InitializeSliders()
    {
        Material referenceMat = GetFirstValidMaterial();
        if (referenceMat == null)
            return;

        if (waterAmountSlider != null && referenceMat.HasProperty(WaterAmountID))
        {
            waterAmountSlider.minValue = 0f;
            waterAmountSlider.maxValue = 1f;
            waterAmountSlider.SetValueWithoutNotify(referenceMat.GetFloat(WaterAmountID));
        }

        if (snowAmountSlider != null && referenceMat.HasProperty(SnowAmountID))
        {
            snowAmountSlider.minValue = 0f;
            snowAmountSlider.maxValue = 1f;
            snowAmountSlider.SetValueWithoutNotify(referenceMat.GetFloat(SnowAmountID));
        }
    }

    public virtual void SetWaterAmount(float value)
    {
        ApplyFloatProperty(WaterAmountID, Mathf.Clamp01(value));
    }

    public virtual void SetSnowAmount(float value)
    {
        ApplyFloatProperty(SnowAmountID, Mathf.Clamp01(value));
    }

    protected void ApplyFloatProperty(int propertyID, float value)
    {
        if (targetRenderers == null)
            return;

        for (int i = 0; i < targetRenderers.Length; i++)
        {
            if (targetRenderers[i] == null)
                continue;

            Material mat = modifySharedMaterial
                ? targetRenderers[i].sharedMaterial
                : targetRenderers[i].material;

            if (mat != null && mat.HasProperty(propertyID))
            {
                mat.SetFloat(propertyID, value);
            }
        }
    }

    private Material GetFirstValidMaterial()
    {
        if (targetRenderers == null)
            return null;

        for (int i = 0; i < targetRenderers.Length; i++)
        {
            if (targetRenderers[i] != null && targetRenderers[i].sharedMaterial != null)
                return targetRenderers[i].sharedMaterial;
        }

        return null;
    }
}