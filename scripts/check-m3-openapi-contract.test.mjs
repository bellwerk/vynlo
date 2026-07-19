import assert from "node:assert/strict";
import test from "node:test";

import {
  documentedComponentParameters,
  documentedOperations,
  documentedQueryParameters,
  queryParameterParityErrors,
  routeOperationsFromSource,
} from "./check-m3-openapi-contract.mjs";

const routeFixture = `
export async function GET(request) {
  const url = new URL(request.url);
  const query = url.searchParams;
  return Response.json({
    dealId: url.searchParams.get("deal_id"),
    statuses: query.getAll("status"),
  });
}

export async function POST(request) {
  return Response.json(await request.json(), { status: 201 });
}

function unrelatedHelper(request) {
  return new URL(request.url).searchParams.get("must_not_leak_into_post");
}
`;

const contractFixture = `
paths:
  /activities:
    get:
      operationId: listActivities
      parameters:
      - name: deal_id
        in: query
      - $ref: '#/components/parameters/StatusFilter'
      responses: {}
    post:
      operationId: createActivity
      parameters:
      - name: ignored_filter
        in: query
      responses: {}
components:
  parameters:
    StatusFilter:
      name: status
      in: query
  responses: {}
`;

test("extracts URL query usage independently for each route method", () => {
  const operations = routeOperationsFromSource(routeFixture, "/activities");

  assert.deepEqual(
    [...operations.get("get /activities").queryParameters].sort(),
    ["deal_id", "status"],
  );
  assert.deepEqual([...operations.get("post /activities").queryParameters], []);
});

test("resolves inline and component query parameters from each operation", () => {
  const documented = documentedOperations(contractFixture);
  const components = documentedComponentParameters(contractFixture);

  assert.deepEqual(
    [
      ...documentedQueryParameters(
        documented.operations.get("get /activities"),
        components,
      ),
    ].sort(),
    ["deal_id", "status"],
  );
  assert.deepEqual(
    [
      ...documentedQueryParameters(
        documented.operations.get("post /activities"),
        components,
      ),
    ],
    ["ignored_filter"],
  );
});

test("fails both undocumented reads and documented-but-ignored filters", () => {
  assert.deepEqual(
    queryParameterParityErrors(
      "get /activities",
      new Set(["deal_id", "status"]),
      new Set(["deal_id"]),
    ),
    ["get /activities reads undocumented query parameter: status"],
  );
  assert.deepEqual(
    queryParameterParityErrors(
      "post /activities",
      new Set(),
      new Set(["ignored_filter"]),
    ),
    ["post /activities documents ignored query parameter: ignored_filter"],
  );
  assert.deepEqual(
    queryParameterParityErrors(
      "post /activities",
      new Set(["implemented_option"]),
      new Set(["implemented_option"]),
    ),
    [],
  );
});
