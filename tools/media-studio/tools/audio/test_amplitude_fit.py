"""Check source fitting with known signals and bounded near-duplicate trajectories."""
import unittest
import numpy as np
from amplitude_fit import refine_amplitudes

class SourceFitTests(unittest.TestCase):
    def fixture(self):
        t=np.arange(24000)/24000
        mono=.2*np.sin(2*np.pi*440*t)+.1*np.sin(2*np.pi*880*t+.4)
        source=np.column_stack((mono,mono));data=np.zeros((60,16,4),dtype='<u2')
        for slot,hz,gain in [(0,440,.15),(1,880,.08)]:
            data[:,slot,0]=round(np.log(hz/20)/np.log(440)*65534)+1
            data[:,slot,1]=round((20*np.log10(gain)+100)/100*65534)+1
            data[:,slot,2]=32768;data[:,slot,3]=12345+slot
        return source,data
    def test_known_amplitudes_move_toward_source(self):
        source,data=self.fixture();result=refine_amplitudes(source,24000,60,data)
        gain=10**(((result[30,:2,1].astype(float)-1)/65534*100-100)/20)
        np.testing.assert_allclose(gain,[.2*np.sqrt(2),.1*np.sqrt(2)],atol=.006)
    def test_only_amplitudes_change(self):
        source,data=self.fixture();result=refine_amplitudes(source,24000,60,data)
        np.testing.assert_array_equal(result[:,:,[0,2,3]],data[:,:,[0,2,3]])
        np.testing.assert_array_equal(result[:,2:],data[:,2:])
        self.assertFalse(np.shares_memory(result,data))
    def test_silent_source_reduces_tone_energy(self):
        source,data=self.fixture();result=refine_amplitudes(np.zeros_like(source),24000,60,data)
        self.assertTrue(np.all(result[:,:,1]==0))
    def test_near_duplicate_tones_remain_bounded(self):
        source,data=self.fixture();data[:,1,0]=data[:,0,0]
        result=refine_amplitudes(source*10,24000,60,data)
        old=10**(((data[:,:2,1].astype(float)-1)/65534*100-100)/20)
        new=10**(((result[:,:2,1].astype(float)-1)/65534*100-100)/20)
        self.assertTrue(np.all(new <= old*3.001))
    def test_timeline_mismatch_is_rejected(self):
        source,data=self.fixture()
        with self.assertRaises(ValueError):refine_amplitudes(source,24000,60,data[:-1])
    def test_invalid_settings_are_rejected(self):
        source,data=self.fixture()
        for rate,fps,size,ridge in [(48000,60,2048,.01),(24000,1,2048,.01),(24000,60,129,.01),(24000,60,2048,0)]:
            with self.subTest(settings=(rate,fps,size,ridge)):
                with self.assertRaises(ValueError):refine_amplitudes(source,rate,fps,data,size,ridge)
if __name__=='__main__':unittest.main()
