const int kqStandardRemoteStreamQuality = 150;
const int kqHighDefinitionRemoteStreamQuality = 150;
const double kqStandardRemoteBlurSigma = 0.6;

int kqRemoteStreamQuality({required bool highDefinition}) {
  return highDefinition
      ? kqHighDefinitionRemoteStreamQuality
      : kqStandardRemoteStreamQuality;
}

bool kqRemoteProfileRequiresMembership({required bool highDefinition}) {
  return highDefinition;
}
