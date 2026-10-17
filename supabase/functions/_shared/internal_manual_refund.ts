/** Fields for recording a buyer refund that is fulfilled by admin GCash only. */
export function internalManualRefundOutcome() {
  return {
    provider: "internal" as const,
    paymongoRefundId: null as string | null,
    providerStatus: "manual_gcash_pending",
    providerError: null as string | null,
    transferLink: null as string | null,
    transferLinkExpiresAt: null as string | null,
  };
}
