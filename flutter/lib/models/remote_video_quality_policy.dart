const int kqStandardRemoteStreamQuality = 80;
const int kqHighDefinitionRemoteStreamQuality = 150;

int kqRemoteStreamQuality({required bool highDefinition}) {
  return highDefinition
      ? kqHighDefinitionRemoteStreamQuality
      : kqStandardRemoteStreamQuality;
}

bool kqRemoteProfileRequiresMembership({required bool highDefinition}) {
  return highDefinition;
}
