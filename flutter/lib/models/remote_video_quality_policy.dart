const int kqStandardRemoteStreamQuality = 100;
const int kqHighDefinitionRemoteStreamQuality = 150;
const double kqStandardRemoteBlurSigma = 0.0;

int kqRemoteStreamQuality({required bool highDefinition}) {
  return highDefinition
      ? kqHighDefinitionRemoteStreamQuality
      : kqStandardRemoteStreamQuality;
}

bool kqRemoteProfileRequiresMembership({required bool highDefinition}) {
  return highDefinition;
}
