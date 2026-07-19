import { NativeSelect } from "@vynlo/ui-web/components/native-select";

interface WorkspaceOption {
  readonly id: string;
  readonly name: string;
}

interface WorkspaceSwitcherProps {
  readonly label: string;
  readonly options: readonly WorkspaceOption[];
  readonly selectedWorkspaceId: string;
}

export function WorkspaceSwitcher({
  label,
  options,
  selectedWorkspaceId,
}: WorkspaceSwitcherProps) {
  return (
    <label className="workspace-switcher">
      <span className="control-label">{label}</span>
      <NativeSelect
        defaultValue={selectedWorkspaceId}
        disabled={options.length < 2}
        name="workspace"
      >
        {options.map((workspace) => (
          <option key={workspace.id} value={workspace.id}>
            {workspace.name}
          </option>
        ))}
      </NativeSelect>
    </label>
  );
}
