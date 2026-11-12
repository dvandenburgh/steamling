import { AddGameSection } from "../components/AddGame";
import { FileSharing } from "../components/FileSharing";
import { SaveSync } from "../components/SaveSync";
import { SdCard } from "../components/SdCard";
import { UsbTransfer } from "../components/UsbTransfer";

// Getting games and files onto the handheld. SD card last: formatting is the only destructive
// action, kept away from the casual toggles.
export function Files() {
  return (
    <>
      <AddGameSection />
      <FileSharing />
      <SaveSync />
      <UsbTransfer />
      <SdCard />
    </>
  );
}
