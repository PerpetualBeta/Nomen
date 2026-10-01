# Nomen — names your screenshots by what they show.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. SPM project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := Nomen
BUNDLE_TYPE      := app
PRODUCT_NAME     := Nomen.app
BUNDLE_ID        := cc.jorviksoftware.Nomen
BUILD_SYSTEM     := spm
SPM_PRODUCT      := Nomen

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := Nomen.entitlements

include ../jorvik-release/release.mk
