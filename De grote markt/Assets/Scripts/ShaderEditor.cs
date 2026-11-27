using UnityEngine;
// [CHANGED]: Removed UnityEngine.UI since sliders now call the methods directly via Inspector events

public class WeatherShaderUIController : MonoBehaviour
{
    [Header("Target Renderers")]
    [Tooltip("All floor/tile renderers using Custom/VR_Reflective_Tile_Water.")]
    [SerializeField] private Renderer[] targetRenderers;

    [Tooltip("If true, edits the shared material asset directly (changes persist after Play Mode).")]
    [SerializeField] private bool modifySharedMaterial = false;

    // [CHANGED]: Removed waterAmountSlider, snowAmountSlider, OnEnable, OnDisable, and InitializeSliders

    private static readonly int WaterAmountID = Shader.PropertyToID("_WaterAmount");
    private static readonly int SnowAmountID = Shader.PropertyToID("_SnowAmount");

    // [CHANGED]: Drag this component into the Water Slider's OnValueChanged (Dynamic float) slot
    public virtual void SetWaterAmount(float value)
    {
        ApplyFloatProperty(WaterAmountID, Mathf.Clamp01(value));
    }

    // [CHANGED]: Drag this component into the Snow Slider's OnValueChanged (Dynamic float) slot
    public virtual void SetSnowAmount(float value)
    {
        ApplyFloatProperty(SnowAmountID, Mathf.Clamp01(value));
    }

    // [CHANGED]: Added a generic helper so you can also wire up any other float shader property from a slider if needed
    public virtual void SetCustomFloatProperty(string propertyName, float value)
    {
        if (string.IsNullOrEmpty(propertyName))
            return;

        ApplyFloatProperty(Shader.PropertyToID(propertyName), value);
    }

    protected virtual void ApplyFloatProperty(int propertyID, float value)
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
}