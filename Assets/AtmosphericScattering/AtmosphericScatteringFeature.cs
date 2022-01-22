namespace UnityEngine.Rendering.Universal
{
    public enum BufferType
    {
        CameraColor,
        Custom 
    }

    public class AtmosphericScatteringFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;

            public Material blitMaterial = null;
            public int blitMaterialPassIndex = -1;
            public BufferType sourceType = BufferType.CameraColor;
            public BufferType destinationType = BufferType.CameraColor;
            public string sourceTextureId = "_SourceTexture";
            public string destinationTextureId = "_DestinationTexture";
            
            [Space]
            public ComputeShader opticalDepthCompute;
            public int textureSize = 256;

            public int inScatteringPoints = 10;
            public int opticalDepthPoints = 10;
            public float densityFalloff = 12f;
            [Range(0,5)]
            public float atmosphereHeight = 1.1f;
            public Vector3 planetLocation = new Vector3(0,-1.272e+07f,0);
            public int planetSize = 6360000;
            
            public float scatteringStrength = 2;
            public Vector3 waveLengths = new Vector3 (700, 530, 460);

            [Header("Volumetric Light")]

            public float lightPower = 1;

            [Range(0,1)]
            public float lightScattering = 0.7f;
            
            public int lightDistance = 100;
            [Range(1, 20)]
            public int lightStepSize = 1;
            
            // public int shadowSteps = 100;
            // [Range(1, 20)]
            // public int shadowStepSize = 1;

            public float depthDistance = 500;

            // public Texture2D blueNoise;
            // public RenderTexture opticalDepthTexture;
            public RenderTexture opticalDepthTexture { get; set; }
        }

        public Settings settings = new Settings();
        AtmosphericScatteringPass blitPass;

        public override void Create()
        {
            blitPass = new AtmosphericScatteringPass(name);
        }

        
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (settings.blitMaterial == null)
            {
                Debug.LogWarningFormat("Missing Blit Material. {0} blit pass will not execute. Check for missing reference in the assigned renderer.", GetType().Name);
                return;
            }

            blitPass.renderPassEvent = settings.renderPassEvent;
            blitPass.settings = settings;
            renderer.EnqueuePass(blitPass);
        }
    }
}