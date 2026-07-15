export function GET() {
  return Response.json({ data: { service: "web", status: "ok" } });
}
