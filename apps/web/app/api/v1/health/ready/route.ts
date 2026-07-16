export function GET() {
  return Response.json({
    data: { checks: [], service: "web", status: "ready" },
  });
}
