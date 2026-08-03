const int kqStandardRemoteStreamQuality = 35;
const int kqHighDefinitionRemoteStreamQuality = 150;
const int kqStandardRemoteMaxFrameHeight = 480;
const int kqHighDefinitionRemoteMaxFrameHeight = 1080;

int kqRemoteStreamQuality({required bool highDefinition}) {
  return highDefinition
      ? kqHighDefinitionRemoteStreamQuality
      : kqStandardRemoteStreamQuality;
}

int kqRemoteMaxFrameHeight({required bool highDefinition}) {
  return highDefinition
      ? kqHighDefinitionRemoteMaxFrameHeight
      : kqStandardRemoteMaxFrameHeight;
}

bool kqRemoteProfileRequiresMembership({required bool highDefinition}) {
  return highDefinition;
}
