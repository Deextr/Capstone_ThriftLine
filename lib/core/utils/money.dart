/// Converts a peso amount to PayMongo's minor unit (centavos).
/// Matches Postgres `round(total_amount * 100)::integer`.
int phpPesosToCentavos(num pesos) {
  if (pesos.isNaN || pesos.isInfinite) return 0;
  return (pesos * 100).round();
}
