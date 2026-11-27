using UnityEngine;

public class PlayerBlockScript : MonoBehaviour
{
    [Header("Target")]
    [SerializeField] private GameObject engel;

    [Header("Pull Settings")]
    public float pullMultiplier = 2f;
    public float maxPullSpeed = 20f;
    public float accelerationSmoothTime = 0.25f; // How smoothly the pull ramps up/down
    public float minPullDistance = 0.5f;         // Prevents jitter right at the edge

    private CharacterController controller;
    private bool isOutside = false;
    private float currentSpeed = 0f;
    private float speedVelocity = 0f;

    void Start()
    {
        controller = GetComponent<CharacterController>();
    }

    void OnTriggerEnter(Collider other)
    {
        // Only react to the engel's trigger, not random objects
        if (other.gameObject == engel)
        {
            isOutside = false;
        }
    }

    void OnTriggerExit(Collider other)
    {
        if (other.gameObject == engel)
        {
            isOutside = true;
        }
    }

    void Update()
    {
        if (engel == null) return;

        float distance = Vector3.Distance(transform.position, engel.transform.position);
        float targetSpeed = 0f;

        // Only calculate a pull speed if outside the trigger AND past the deadzone
        if (isOutside && distance > minPullDistance)
        {
            targetSpeed = Mathf.Min(distance * pullMultiplier, maxPullSpeed);
        }

        // Smoothly accelerate toward targetSpeed (and smoothly decelerate back to 0)
        currentSpeed = Mathf.SmoothDamp(currentSpeed, targetSpeed, ref speedVelocity, accelerationSmoothTime);

        if (currentSpeed > 0.01f)
        {
            Vector3 pullDirection = (engel.transform.position - transform.position).normalized;
            controller.Move(pullDirection * currentSpeed * Time.deltaTime);
        }
    }
}
