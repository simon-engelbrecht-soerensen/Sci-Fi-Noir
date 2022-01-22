namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// Draws full screen mesh using given material and pass and reading from source target.
    /// </summary>
    internal class AtmosphericScatteringPass : ScriptableRenderPass
    {
        public FilterMode filterMode { get; set; }
        public AtmosphericScatteringFeature.Settings settings;

        RenderTargetIdentifier source;
        RenderTargetIdentifier destination;
        // RTHandle destination2;
        int temporaryRTId = Shader.PropertyToID("_TempRT");

        int sourceId;
        int destinationId;
        int destination2Id;
        bool isSourceAndDestinationSameTarget;

        string m_ProfilerTag;
        
        private static readonly int ScatteringCoefficients = Shader.PropertyToID("scatteringCoefficients");
        private static readonly int ScatteringPoints = Shader.PropertyToID("_ScatteringPoints");
        private static readonly int OpticalDepthPoints = Shader.PropertyToID("_OpticalDepthPoints");
        private static readonly int DensityFalloff = Shader.PropertyToID("_DensityFalloff");
        private static readonly int AtmosphereRadius = Shader.PropertyToID("_AtmosphereRadius");
        private static readonly int PlanetSize = Shader.PropertyToID("_PlanetSize");

        private int textureSize = 256;
        private static readonly int BakedOpticalDepth = Shader.PropertyToID("_BakedOpticalDepth");
        bool settingsUpToDate;
        private static readonly int PlanetLocation = Shader.PropertyToID("_PlanetLocation");

        private RenderTexture target;
        private RenderTexture converged;
        private static readonly int LightDistance = Shader.PropertyToID("_LightDistance");
        private static readonly int LightPower = Shader.PropertyToID("_LightPower");
        private static readonly int SunLightScattering = Shader.PropertyToID("_SunLightScattering");
        private static readonly int LightStepSize = Shader.PropertyToID("_LightStepSize");
        private static readonly int DepthDistance = Shader.PropertyToID("_DepthDistance");

        public AtmosphericScatteringPass(string tag)
        {
            m_ProfilerTag = tag;
            
            target = new RenderTexture(256, 256, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.sRGB);
            target.enableRandomWrite = true;
            target.Create();

            // converged = new RenderTexture(256, 256, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.sRGB);
            // converged.enableRandomWrite = true;
            // converged.Create();
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
           
            // settingsUpToDate = true;
            base.Configure(cmd, cameraTextureDescriptor);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            float atmosphereRadius = (1 + settings.atmosphereHeight) * settings.planetSize;
            
            float scatterX = Mathf.Pow(400 / settings.waveLengths.x, 4);
            float scatterY = Mathf.Pow (400 / settings.waveLengths.y, 4);
            float scatterZ = Mathf.Pow (400 / settings.waveLengths.z, 4);
            settings.blitMaterial.SetVector (ScatteringCoefficients, new Vector3 (scatterX, scatterY, scatterZ) * settings.scatteringStrength);
            settings.blitMaterial.SetInt (ScatteringPoints, settings.inScatteringPoints);
            settings.blitMaterial.SetInt (OpticalDepthPoints, settings.opticalDepthPoints);
            settings.blitMaterial.SetFloat (AtmosphereRadius, atmosphereRadius);
            settings.blitMaterial.SetVector(PlanetLocation, settings.planetLocation);
            settings.blitMaterial.SetFloat (PlanetSize, settings.planetSize);
            settings.blitMaterial.SetFloat (DensityFalloff, settings.densityFalloff);
            
            settings.blitMaterial.SetFloat (LightPower, settings.lightPower);
            settings.blitMaterial.SetFloat (SunLightScattering, settings.lightScattering);
            settings.blitMaterial.SetInt (LightDistance, settings.lightDistance);
            settings.blitMaterial.SetInt (LightStepSize, settings.lightStepSize);
            // settings.blitMaterial.SetInt ("_ShadowSteps", settings.shadowSteps);
            // settings.blitMaterial.SetInt ("_ShadowStepSize", settings.shadowStepSize);
            
            settings.blitMaterial.SetFloat (DepthDistance, settings.depthDistance);
            // settings.blitMaterial.SetTexture("_BlueNoise", settings.blueNoise);

            RenderTextureDescriptor blitTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            blitTargetDescriptor.depthBufferBits = 0;
            
            cmd.GetTemporaryRT(BakedOpticalDepth, blitTargetDescriptor, filterMode);
            // destination2 = new RenderTargetIdentifier(BakedOpticalDepth);
            
            // destination2Id = BakedOpticalDepth;
            
            

            isSourceAndDestinationSameTarget = settings.sourceType == settings.destinationType &&
                (settings.sourceType == BufferType.CameraColor || settings.sourceTextureId == settings.destinationTextureId);

            var renderer = renderingData.cameraData.renderer;

            if (settings.sourceType == BufferType.CameraColor)
            {
                sourceId = -1;
                source = renderer.cameraColorTarget;
            }
            else
            {
                sourceId = Shader.PropertyToID(settings.sourceTextureId);
                cmd.GetTemporaryRT(sourceId, blitTargetDescriptor, filterMode);
                source = new RenderTargetIdentifier(sourceId);
            }

            if (isSourceAndDestinationSameTarget)
            {
                destinationId = temporaryRTId;
                cmd.GetTemporaryRT(destinationId, blitTargetDescriptor, filterMode);
                destination = new RenderTargetIdentifier(destinationId);
            }
            else if (settings.destinationType == BufferType.CameraColor)
            {
                destinationId = -1;
                destination = renderer.cameraColorTarget;
            }
            else
            {
                destinationId = Shader.PropertyToID(settings.destinationTextureId);
                cmd.GetTemporaryRT(destinationId, blitTargetDescriptor, filterMode);
                destination = new RenderTargetIdentifier(destinationId);
            }
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);

            // int kernelHandle = settings.opticalDepthCompute.FindKernel("CSMain");
            // PrecomputeOutScattering(cmd, kernelHandle);
            
            
            // Blit(cmd, target, BakedOpticalDepth);
            // Blit(cmd, target, converged, settings.blitMaterial);
            // settings.blitMaterial.SetTexture(BakedOpticalDepth, target);

            // Can't read and write to same color target, create a temp render target to blit. 
            if (isSourceAndDestinationSameTarget)
            {
                Blit(cmd, source, destination, settings.blitMaterial, settings.blitMaterialPassIndex);
                Blit(cmd, destination, source);
            }
            else
            {
                Blit(cmd, source, destination, settings.blitMaterial, settings.blitMaterialPassIndex);
            }

            // settings.blitMaterial.SetTexture(BakedOpticalDepth, target);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        /// <inheritdoc/>
        public override void FrameCleanup(CommandBuffer cmd)
        {
            if (destinationId != -1)
                cmd.ReleaseTemporaryRT(destinationId);

            if (source == destination && sourceId != -1) 
                cmd.ReleaseTemporaryRT(sourceId);
        }
        
        void PrecomputeOutScattering (CommandBuffer cmd, int kernelHandle)
        {
            // var settingsOpticalDepthTexture = settings.opticalDepthTexture;
            
            cmd.SetComputeIntParam(settings.opticalDepthCompute, "textureSize", textureSize);
            cmd.SetComputeIntParam(settings.opticalDepthCompute, "numOutScatteringSteps", settings.opticalDepthPoints);
            cmd.SetComputeFloatParam(settings.opticalDepthCompute, "atmosphereRadius", (1 + settings.atmosphereHeight));
            cmd.SetComputeFloatParam(settings.opticalDepthCompute, "densityFalloff", settings.densityFalloff);
            cmd.SetComputeVectorParam(settings.opticalDepthCompute, "planetLocation", settings.planetLocation);
            
            cmd.SetComputeTextureParam(settings.opticalDepthCompute, kernelHandle, "Result", target);

            
            cmd.DispatchCompute(settings.opticalDepthCompute, kernelHandle, Mathf.CeilToInt(Screen.width / 8), Mathf.CeilToInt(Screen.height / 8), 1);
            
            // if (/*!settingsUpToDate ||*/ settingsOpticalDepthTexture == null || !settingsOpticalDepthTexture.IsCreated ()) 
            // {
            //     // ComputeHelper.CreateRenderTexture (ref settingsOpticalDepthTexture, textureSize, FilterMode.Bilinear);
            //     settings.opticalDepthCompute.SetTexture (0, "Result", settingsOpticalDepthTexture);
            //     settings.opticalDepthCompute.SetInt ("textureSize", textureSize);
            //     settings.opticalDepthCompute.SetInt ("numOutScatteringSteps", settings.opticalDepthPoints);
            //     settings.opticalDepthCompute.SetFloat ("atmosphereRadius", (1 + settings.atmosphereHeight));
            //     settings.opticalDepthCompute.SetFloat ("densityFalloff", settings.densityFalloff);
            //     settings.opticalDepthCompute.SetVector ("planetLocation", settings.planetLocation);
            //     // settings.opticalDepthCompute.SetVector ("params", testParams);
            //     settings.opticalDepthTexture = settingsOpticalDepthTexture;
            //     // ComputeHelper.Run (settings.opticalDepthCompute, textureSize, textureSize);
            // } 
        }
    }
}
